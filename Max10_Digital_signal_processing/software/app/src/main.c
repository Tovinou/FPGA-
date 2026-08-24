#include <stdio.h>

#include "timer_hw_ip_test.h"
#include "adc_test.h"
#include "pio_led_test.h"
#include "irq_test.h"

int main(void)
{
    int failures = 0;

    failures += timer_hw_ip_test();
    failures += adc_test();
    failures += pio_led_test();
    failures += irq_test();
    printf("All hardware tests complete: %d failure(s)\n", failures);
    return failures != 0;
}