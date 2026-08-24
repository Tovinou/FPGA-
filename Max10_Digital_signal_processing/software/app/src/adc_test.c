#include <stdio.h>
#include <stdint.h>

#include "system.h"
#include "altera_modular_adc.h"
#include "altera_modular_adc_sequencer_regs.h"
#include "altera_modular_adc_sample_store_regs.h"
#include "test_common.h"

#define ADC_WAIT_COUNT 50000U

int adc_test(void)
{
    uint32_t samples[4];
    uint32_t command;
    unsigned int i;
    unsigned int wait;
    int failures = 0;
    int read_result;
    alt_modular_adc_dev *device;

    printf("modular ADC test, sample=0x%08x sequencer=0x%08x\n",
           (unsigned int)MODULAR_ADC_0_SAMPLE_STORE_CSR_BASE,
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

    adc_clear_interrupt_status(MODULAR_ADC_0_SAMPLE_STORE_CSR_BASE);
    adc_interrupt_enable(MODULAR_ADC_0_SAMPLE_STORE_CSR_BASE);
    for (wait = 0; wait < ADC_WAIT_COUNT; ++wait)
    {
        if (adc_interrupt_asserted(MODULAR_ADC_0_SAMPLE_STORE_CSR_BASE))
        {
            break;
        }
    }
    failures += test_check("ADC sample-store interrupt arrives", wait < ADC_WAIT_COUNT);

    read_result = alt_adc_word_read(
        MODULAR_ADC_0_SAMPLE_STORE_CSR_BASE, samples, 4U);
    failures += test_check("ADC sample-store read succeeds", read_result == 0);
    for (i = 0; i < 4U; ++i)
    {
        printf("ADC CH0 sample[%u] = 0x%08x\n", i, (unsigned int)samples[i]);
    }

    adc_clear_interrupt_status(MODULAR_ADC_0_SAMPLE_STORE_CSR_BASE);
    failures += test_check("ADC interrupt status clears",
                           !adc_interrupt_asserted(MODULAR_ADC_0_SAMPLE_STORE_CSR_BASE));
    adc_interrupt_disable(MODULAR_ADC_0_SAMPLE_STORE_CSR_BASE);

    adc_stop(MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    adc_set_mode_run_once(MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    adc_start(MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    command = IORD_ALTERA_MODULAR_ADC_SEQUENCER_CMD_REG(
        MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    failures += test_check("ADC one-shot mode starts",
                           (command & ALTERA_MODULAR_ADC_SEQUENCER_CMD_RUN_MSK) != 0U);
    adc_stop(MODULAR_ADC_0_SEQUENCER_CSR_BASE);

    adc_recalibrate(MODULAR_ADC_0_SEQUENCER_CSR_BASE);
    printf("ADC recalibration returned\n");
    return failures;
}