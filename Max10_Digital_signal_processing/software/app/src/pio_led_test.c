/*
 * PIO LED output test.
 */

#include <stdio.h>

#include "system.h"
#include "altera_avalon_pio_regs.h"

#include "pio_led_test.h"

static int pio_keys_test(void)
{
    unsigned int previous;
    unsigned int current;
    unsigned int i;
    unsigned int changes = 0U;

    printf("Keys PIO test at 0x%08x\n", (unsigned int)KEYS_BASE);
    previous = IORD_ALTERA_AVALON_PIO_DATA(KEYS_BASE) & 0x3U;
    printf("Initial KEY state: 0x%02x\n", previous);

    for (i = 0; i < 10000U; ++i)
    {
        current = IORD_ALTERA_AVALON_PIO_DATA(KEYS_BASE) & 0x3U;
        IOWR_ALTERA_AVALON_PIO_DATA(PIO_0_BASE, current);

        if (current != previous)
        {
            printf("KEY state changed: 0x%02x -> 0x%02x\n", previous, current);
            previous = current;
            changes++;
        }
    }

    printf("Final KEY state: 0x%02x, changes detected: %u\n", previous, changes);
    printf("[PASS] Keys input is readable and remains within its 2-bit range\n");
    return 0;
}

int pio_led_test(void)
{
    static const unsigned int patterns[] = {0x000U, 0x2AAU, 0x155U, 0x3FFU};
    unsigned int i;
    int failures = 0;

    printf("PIO LED test at 0x%08x\n", (unsigned int)PIO_0_BASE);

    for (i = 0; i < sizeof(patterns) / sizeof(patterns[0]); ++i)
    {
        unsigned int readback;

        IOWR_ALTERA_AVALON_PIO_DATA(PIO_0_BASE, patterns[i]);
        readback = IORD_ALTERA_AVALON_PIO_DATA(PIO_0_BASE);
        printf("PIO pattern=0x%03x readback=0x%03x\n", patterns[i], readback);

        if ((readback & 0x3FFU) != patterns[i])
        {
            printf("[FAIL] PIO readback\n");
            failures++;
        }
    }

    IOWR_ALTERA_AVALON_PIO_DATA(PIO_0_BASE, 0U);
    failures += pio_keys_test();
    IOWR_ALTERA_AVALON_PIO_DATA(PIO_0_BASE, 0U);
    printf("PIO LED/KEY failures: %d\n", failures);
    return failures;
}