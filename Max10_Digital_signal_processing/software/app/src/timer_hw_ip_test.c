#include <stdio.h>
#include <stdint.h>

#include "system.h"
#include "timer_hw_ip.h"
#include "test_common.h"

#define TIMER_WAIT_COUNT 2000U

static uint32_t timer_status_read(void)
{
    return (uint32_t)TIMER_READ_STATUS();
}

static int test_reset_and_stop(void)
{
    int failures = 0;

    TIMER_WRITE_CONTROL(TIMER_MODE_RESET);
    test_wait_cycles(2U, timer_status_read);
    failures += test_check("timer reset clears value", TIMER_READ_VALUE() == 0U);
    failures += test_check("timer reset clears running",
                           (TIMER_READ_STATUS() & TIMER_STATUS_RUNNING) == 0U);

    TIMER_WRITE_CONTROL(TIMER_MODE_START);
    test_wait_cycles(10U, timer_status_read);
    failures += test_check("timer start sets running",
                           (TIMER_READ_STATUS() & TIMER_STATUS_RUNNING) != 0U);

    TIMER_WRITE_CONTROL(TIMER_MODE_STOP);
    test_wait_cycles(2U, timer_status_read);
    failures += test_check("timer stop clears running",
                           (TIMER_READ_STATUS() & TIMER_STATUS_RUNNING) == 0U);
    return failures;
}

static int test_load_and_counting(void)
{
    uint32_t before;
    uint32_t after;
    int failures = 0;

    TIMER_WRITE_LOAD(10U);
    TIMER_WRITE_CONTROL(TIMER_MODE_LOAD);
    test_wait_cycles(2U, timer_status_read);
    failures += test_check("timer load writes value", TIMER_READ_VALUE() == 10U);

    before = TIMER_READ_VALUE();
    TIMER_WRITE_CONTROL(TIMER_PRESCALER_1 | TIMER_MODE_START);
    test_wait_cycles(TIMER_WAIT_COUNT, timer_status_read);
    after = TIMER_READ_VALUE();
    TIMER_WRITE_CONTROL(TIMER_MODE_STOP);
    failures += test_check("timer counts up", after > before);

    TIMER_WRITE_LOAD(100U);
    TIMER_WRITE_CONTROL(TIMER_MODE_LOAD);
    test_wait_cycles(2U, timer_status_read);
    before = TIMER_READ_VALUE();
    TIMER_WRITE_CONTROL(TIMER_COUNTDOWN | TIMER_PRESCALER_1 | TIMER_MODE_START);
    test_wait_cycles(TIMER_WAIT_COUNT, timer_status_read);
    after = TIMER_READ_VALUE();
    TIMER_WRITE_CONTROL(TIMER_MODE_STOP);
    failures += test_check("timer counts down", after < before);
    return failures;
}

static int test_prescalers(void)
{
    static const uint8_t values[] = {
        TIMER_PRESCALER_1, TIMER_PRESCALER_2, TIMER_PRESCALER_4,
        TIMER_PRESCALER_8, TIMER_PRESCALER_16, TIMER_PRESCALER_32,
        TIMER_PRESCALER_64, TIMER_PRESCALER_128
    };
    static const unsigned int names[] = {1U, 2U, 4U, 8U, 16U, 32U, 64U, 128U};
    unsigned int i;
    int failures = 0;

    for (i = 0; i < sizeof(values) / sizeof(values[0]); ++i)
    {
        TIMER_WRITE_LOAD(0U);
        TIMER_WRITE_CONTROL(TIMER_MODE_LOAD);
        TIMER_WRITE_CONTROL(values[i] | TIMER_MODE_START);
        test_wait_cycles(TIMER_WAIT_COUNT, timer_status_read);
        TIMER_WRITE_CONTROL(TIMER_MODE_STOP);
        printf("timer prescaler /%u value=0x%08x\n",
               names[i], (unsigned int)TIMER_READ_VALUE());
        failures += test_check("timer prescaler readback",
                               (TIMER_READ_CONTROL() & TIMER_PRESCALER_MASK) == values[i]);
    }
    return failures;
}

static int test_compare_capture_pwm(void)
{
    uint32_t timer_value;
    int failures = 0;

    TIMER_WRITE_LOAD(25U);
    TIMER_WRITE_COMPARE(25U);
    TIMER_WRITE_CONTROL(TIMER_MODE_LOAD);
    test_wait_cycles(2U, timer_status_read);
    failures += test_check("timer compare flag asserts",
                           (TIMER_READ_STATUS() & TIMER_STATUS_COMPARE) != 0U);

    TIMER_WRITE_COMPARE(26U);
    test_wait_cycles(2U, timer_status_read);
    failures += test_check("timer compare flag clears",
                           (TIMER_READ_STATUS() & TIMER_STATUS_COMPARE) == 0U);

    TIMER_WRITE_LOAD(1234U);
    TIMER_WRITE_CONTROL(TIMER_MODE_LOAD);
    test_wait_cycles(2U, timer_status_read);
    timer_value = TIMER_READ_VALUE();
    TIMER_WRITE_CONTROL(TIMER_CAPTURE_ENABLE | TIMER_MODE_STOP);
    test_wait_cycles(2U, timer_status_read);
    failures += test_check("timer software capture is valid",
                           (TIMER_READ_STATUS() & TIMER_STATUS_CAPTURE_VLD) != 0U);
    failures += test_check("timer software capture stores value",
                           TIMER_READ_CAPTURE() == timer_value);

    TIMER_WRITE_LOAD(10U);
    TIMER_WRITE_COMPARE(20U);
    TIMER_WRITE_CONTROL(TIMER_MODE_LOAD);
    test_wait_cycles(2U, timer_status_read);
    TIMER_WRITE_CONTROL(TIMER_PWM_ENABLE | TIMER_MODE_STOP);
    test_wait_cycles(2U, timer_status_read);
    failures += test_check("timer PWM asserts below compare",
                           (TIMER_READ_STATUS() & TIMER_STATUS_PWM_OUT) != 0U);
    TIMER_WRITE_COMPARE(5U);
    test_wait_cycles(2U, timer_status_read);
    failures += test_check("timer PWM deasserts above compare",
                           (TIMER_READ_STATUS() & TIMER_STATUS_PWM_OUT) == 0U);
    return failures;
}

static int test_overflow(void)
{
    int failures = 0;

    TIMER_WRITE_LOAD(0xffffffffU);
    TIMER_WRITE_CONTROL(TIMER_MODE_LOAD);
    TIMER_WRITE_CONTROL(TIMER_PRESCALER_1 | TIMER_MODE_START);
    test_wait_cycles(10U, timer_status_read);
    TIMER_WRITE_CONTROL(TIMER_MODE_STOP);
    failures += test_check("timer count-up overflow asserts",
                           (TIMER_READ_STATUS() & TIMER_STATUS_OVERFLOW) != 0U);

    TIMER_WRITE_CONTROL(TIMER_MODE_RESET);
    TIMER_WRITE_LOAD(0U);
    TIMER_WRITE_CONTROL(TIMER_MODE_LOAD);
    TIMER_WRITE_CONTROL(TIMER_COUNTDOWN | TIMER_PRESCALER_1 | TIMER_MODE_START);
    test_wait_cycles(10U, timer_status_read);
    TIMER_WRITE_CONTROL(TIMER_MODE_STOP);
    failures += test_check("timer count-down overflow asserts",
                           (TIMER_READ_STATUS() & TIMER_STATUS_OVERFLOW) != 0U);

    TIMER_WRITE_CONTROL(TIMER_MODE_RESET);
    failures += test_check("timer reset clears overflow",
                           (TIMER_READ_STATUS() & TIMER_STATUS_OVERFLOW) == 0U);
    return failures;
}

int timer_hw_ip_test(void)
{
    int failures = 0;

    printf("TIMER_HW_IP test at 0x%08x\n", (unsigned int)TIMER_IP_BASE);
    failures += test_reset_and_stop();
    failures += test_load_and_counting();
    failures += test_prescalers();
    failures += test_compare_capture_pwm();
    failures += test_overflow();
    TIMER_WRITE_CONTROL(TIMER_MODE_STOP);
    printf("TIMER_HW_IP failures: %d\n", failures);
    return failures;
}