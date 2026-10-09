#include <stdint.h>
#include <stdio.h>

#include "system.h"
#include "io.h"
#include "unistd.h"
#include "altera_avalon_pio_regs.h"
#include "ai.h"

#define AI_WINDOW_SIZE 32U
#define AI_FIFO_LEVEL_OFFSET 8U
#define AI_FIFO_DATA_OFFSET 0U
#define AI_ADC_MIDPOINT 2048
#define AI_FEATURE_SCALE 256
#define AI_CLASS_COUNT 4U

static uint32_t fifo_level(void)
{
    return IORD_32DIRECT(ADC_FIFO_0_BASE, AI_FIFO_LEVEL_OFFSET);
}

static uint16_t fifo_read_sample(void)
{
    return (uint16_t)IORD_32DIRECT(ADC_FIFO_0_BASE, AI_FIFO_DATA_OFFSET);
}

static unsigned int classify_features(int32_t energy, int32_t variation,
                                      int32_t crossings)
{
    static const int16_t weights[AI_CLASS_COUNT][3] = {
        {  64, -16, -16 },
        {  16,  48,  16 },
        {  16,  16,  64 },
        {  48,  32, -32 }
    };
    static const int16_t bias[AI_CLASS_COUNT] = { 128, 64, 64, 32 };
    int32_t scores[AI_CLASS_COUNT];
    unsigned int best = 0U;
    unsigned int class_index;

    for (class_index = 0U; class_index < AI_CLASS_COUNT; ++class_index)
    {
        scores[class_index] = bias[class_index] +
            (weights[class_index][0] * energy) / AI_FEATURE_SCALE +
            (weights[class_index][1] * variation) / AI_FEATURE_SCALE +
            (weights[class_index][2] * crossings) / AI_FEATURE_SCALE;
        if (scores[class_index] > scores[best])
        {
            best = class_index;
        }
    }
    return best;
}

int ai_run_once(unsigned int *output_class)
{
    int32_t samples[AI_WINDOW_SIZE];
    int32_t energy = 0;
    int32_t variation = 0;
    int32_t crossings = 0;
    int32_t previous = 0;
    unsigned int i;
    unsigned int class_index;

    if (fifo_level() < AI_WINDOW_SIZE)
    {
        return 0;
    }

    for (i = 0U; i < AI_WINDOW_SIZE; ++i)
    {
        samples[i] = (int32_t)fifo_read_sample() - AI_ADC_MIDPOINT;
        energy += samples[i] >= 0 ? samples[i] : -samples[i];
        if (i > 0U)
        {
            int32_t delta = samples[i] - previous;
            variation += delta >= 0 ? delta : -delta;
            if ((samples[i] >= 0) != (previous >= 0))
            {
                crossings++;
            }
        }
        previous = samples[i];
    }

    energy = (energy * AI_FEATURE_SCALE) / (AI_WINDOW_SIZE * AI_ADC_MIDPOINT);
    variation = (variation * AI_FEATURE_SCALE) /
                (AI_WINDOW_SIZE * AI_ADC_MIDPOINT);
    crossings = (crossings * AI_FEATURE_SCALE) / AI_WINDOW_SIZE;
    class_index = classify_features(energy, variation, crossings);

    if (output_class != NULL)
    {
        *output_class = class_index;
    }

    printf("AI window=%u energy=%ld variation=%ld crossings=%ld class=%u\n",
           AI_WINDOW_SIZE, (long)energy, (long)variation,
           (long)crossings, class_index);
    return 1;
}

void ai_demo_forever(void)
{
    unsigned int class_index;
    unsigned int window_count = 0U;
    unsigned int led_value;

    printf("AI continuous demo: class on LEDR[4:1], heartbeat on LEDR[9]\n");
    for (;;)
    {
        if (ai_run_once(&class_index) != 0)
        {
            /* LEDR(0) is reserved for PWM by the top-level VHDL mux. */
            led_value = (1U << (class_index + 1U));
            window_count++;
            if ((window_count & 0x1FU) == 0U)
            {
                led_value |= 1U << 9;
            }
            IOWR_ALTERA_AVALON_PIO_DATA(PIO_0_BASE, led_value);
        }
        else
        {
            usleep(1000U);
        }
    }
}
