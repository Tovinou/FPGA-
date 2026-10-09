#include <stdio.h>
#include <stdint.h>

#include "system.h"
#include "altera_modular_adc.h"
#include "altera_modular_adc_sequencer_regs.h"
#include "test_common.h"

#define ADC_WAIT_COUNT 50000U

int adc_test(void)
{
    uint32_t command;
    int failures = 0;
    alt_modular_adc_dev *device;

        printf("modular ADC test, sequencer=0x%08x\n",
            (unsigned int)MODULAR_ADC_0_SEQUENCER_CSR_BASE);

    device = altera_modular_adc_open("/dev/modular_adc_0_sequencer_csr");
    failures += test_check("ADC device opens", device != NULL);

    adc_stop(MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    command = IORD_ALTERA_MODULAR_ADC_SEQUENCER_CMD_REG(
        MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    failures += test_check("ADC stop clears RUN",
                           (command & ALTERA_MODULAR_ADC_SEQUENCER_CMD_RUN_MSK) == 0U);

    adc_set_mode_run_continuously(MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    adc_start(MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    command = IORD_ALTERA_MODULAR_ADC_SEQUENCER_CMD_REG(
        MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    failures += test_check("ADC continuous mode starts",
                           (command & ALTERA_MODULAR_ADC_SEQUENCER_CMD_RUN_MSK) != 0U);

    adc_stop(MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    adc_set_mode_run_once(MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    adc_start(MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    command = IORD_ALTERA_MODULAR_ADC_SEQUENCER_CMD_REG(
        MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    failures += test_check("ADC one-shot mode selected",
                           (command & ALTERA_MODULAR_ADC_SEQUENCER_CMD_MODE_MSK) ==
                           ALTERA_MODULAR_ADC_SEQUENCER_CMD_MODE_ONCE);
    adc_stop(MODULAR_ADC_0_SEQUENCER_CSR_BASE);

    adc_recalibrate(MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    printf("ADC recalibration returned\n");
    return failures;
}