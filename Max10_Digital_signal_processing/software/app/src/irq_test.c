/*
 * TIMER_HW_IP interrupt test.
 */

#include <stdio.h>
#include <stdlib.h>

#include "system.h"
#include "altera_avalon_timer_regs.h"
#include <sys/alt_irq.h>
#include <alt_types.h>

#include "irq_test.h"

#define IRQ_WAIT_LIMIT 1000000U

static volatile int timer_int_count;

static void timer_irq_handler(void *context)
{
    (void)context;

    IOWR_ALTERA_AVALON_TIMER_STATUS(TIMER_IP_BASE, 0);
    timer_int_count++;
}

static void init_timer_irq(void)
{
    IOWR_ALTERA_AVALON_TIMER_PERIODL(TIMER_IP_BASE, 0x0000U);
    IOWR_ALTERA_AVALON_TIMER_PERIODH(TIMER_IP_BASE, 0x0002U);

    alt_ic_isr_register(
        0,
        1,
        timer_irq_handler,
        NULL,
        NULL
    );

    IOWR_ALTERA_AVALON_TIMER_CONTROL(
        TIMER_IP_BASE,
        ALTERA_AVALON_TIMER_CONTROL_CONT_MSK |
        ALTERA_AVALON_TIMER_CONTROL_START_MSK |
        ALTERA_AVALON_TIMER_CONTROL_ITO_MSK
    );
}

int irq_test(void)
{
    volatile unsigned int wait;

    printf("TIMER_HW_IP overflow IRQ test, IRQ=%d\n", 1);
    timer_int_count = 0;
    init_timer_irq();
    alt_irq_cpu_enable_interrupts();

    for (wait = 0; wait < IRQ_WAIT_LIMIT && timer_int_count < 3; ++wait)
    {
        (void)IORD_ALTERA_AVALON_TIMER_STATUS(TIMER_IP_BASE);
    }

    IOWR_ALTERA_AVALON_TIMER_CONTROL(
        TIMER_IP_BASE,
        ALTERA_AVALON_TIMER_CONTROL_STOP_MSK
    );

    if (timer_int_count >= 3)
    {
        printf("[PASS] TIMER_HW_IP interrupts received: %d\n", timer_int_count);
        return 0;
    }

    printf("[FAIL] TIMER_HW_IP interrupts received: %d\n", timer_int_count);
    return 1;
}