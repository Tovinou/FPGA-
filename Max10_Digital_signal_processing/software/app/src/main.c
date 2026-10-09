#include <stdio.h>

#include "timer_hw_ip_test.h"
#include "adc_test.h"
#include "pio_led_test.h"
#include "ai.h"
#include "sdram_test.h"

int main(void)
{
    int failures = 0;

    failures += timer_hw_ip_test();
    failures += adc_test();
    failures += pio_led_test();
    failures += sdram_stress_test(8U);
    printf("All startup tests complete: %d failure(s)\n", failures);
    if (failures == 0)
    {
        ai_demo_forever();
    }
    return failures != 0;
}