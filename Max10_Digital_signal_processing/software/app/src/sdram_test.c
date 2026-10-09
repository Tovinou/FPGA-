#include <stdint.h>
#include <stdio.h>

#include "system.h"
#include "altera_avalon_pio_regs.h"
#include "sdram_test.h"

#define SDRAM_TEST_WORDS (1024U * 1024U)
#define SDRAM_PATTERN_COUNT 4U

static uint16_t pattern(unsigned int pattern_index, unsigned int index)
{
    switch (pattern_index)
    {
        case 0U:
            return 0x0000U;
        case 1U:
            return 0xffffU;
        case 2U:
            return (index & 1U) ? 0xaaaaU : 0x5555U;
        default:
            return (uint16_t)(index ^ (index >> 8));
    }
}

int sdram_stress_test(unsigned int passes)
{
    volatile uint16_t *memory = (volatile uint16_t *)MYCUSTOM_SDRAM_0_BASE;
    unsigned int pass;
    unsigned int pattern_index;
    unsigned int index;
    unsigned int errors = 0U;

    printf("SDRAM stress: %u passes, %u words\n", passes, SDRAM_TEST_WORDS);
    IOWR_ALTERA_AVALON_PIO_DATA(PIO_0_BASE, 0x200U);
    for (pass = 0U; pass < passes; ++pass)
    {
        for (pattern_index = 0U; pattern_index < SDRAM_PATTERN_COUNT; ++pattern_index)
        {
            IOWR_ALTERA_AVALON_PIO_DATA(
                PIO_0_BASE,
                (1U << (pattern_index + 1U)) | ((pass & 1U) << 9));
            for (index = 0U; index < SDRAM_TEST_WORDS; ++index)
            {
                memory[index] = pattern(pattern_index, index);
            }
            for (index = 0U; index < SDRAM_TEST_WORDS; ++index)
            {
                if (memory[index] != pattern(pattern_index, index))
                {
                    errors++;
                    if (errors == 1U)
                    {
                        printf("SDRAM error pass=%u pattern=%u address=0x%08x expected=0x%04x actual=0x%04x\n",
                               pass, pattern_index, (unsigned int)&memory[index],
                               pattern(pattern_index, index), memory[index]);
                    }
                }
            }
        }
        IOWR_ALTERA_AVALON_PIO_DATA(PIO_0_BASE, 0x3ffU);
        printf("SDRAM pass %u complete, errors=%u\n", pass + 1U, errors);
    }

    if (errors == 0U)
    {
        printf("[PASS] SDRAM stress test\n");
        return 0;
    }

    printf("[FAIL] SDRAM stress test errors=%u\n", errors);
    return 1;
}
