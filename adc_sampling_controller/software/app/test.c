#include <stdio.h>
#include <stdint.h>

#include "system.h"
#include "adc_sampling_controller_hw_ip.h"
#include "io.h"
#include "priv/alt_busy_sleep.h"

#define TEST_ADC_BASE        ADC_SAMPLING_CONTROLLER_HW_IP_0_BASE
#define TEST_ADC_CHANNEL     1u
#define TEST_PRESCALER_SEL   0u
#define TEST_SAMPLE_PERIOD   5000u
#define TEST_BUFFER_DEPTH    1024u
#define TEST_SAMPLE_DUMP     32u
#define TEST_POLL_LIMIT      400u

#define TEST_SCAN_ENABLE     0u
#define TEST_SCAN_LEN        1u

#define TEST_TRIGGER_ENABLE        0u
#define TEST_TRIGGER_EDGE_FALLING  0u
#define TEST_TRIGGER_LEVEL         2048u
#define TEST_TRIGGER_CHANNEL       1u
#define TEST_PRE_TRIGGER_COUNT     200u
#define TEST_POST_TRIGGER_COUNT    200u

#define TEST_VREF_VOLTS      3.300

static uint8_t seg7_encode(uint8_t nibble)
{
    switch (nibble & 0xFu) {
    case 0x0u: return 0xC0u;
    case 0x1u: return 0xF9u;
    case 0x2u: return 0xA4u;
    case 0x3u: return 0xB0u;
    case 0x4u: return 0x99u;
    case 0x5u: return 0x92u;
    case 0x6u: return 0x82u;
    case 0x7u: return 0xF8u;
    case 0x8u: return 0x80u;
    case 0x9u: return 0x90u;
    case 0xAu: return 0x88u;
    case 0xBu: return 0x83u;
    case 0xCu: return 0xC6u;
    case 0xDu: return 0xA1u;
    case 0xEu: return 0x86u;
    default:   return 0x8Eu;
    }
}

static void hex_write(uint32_t value, uint32_t status_bits)
{
    IOWR_8DIRECT(HEX0_PIO_BASE, 0, seg7_encode((uint8_t)(value & 0xFu)));
    IOWR_8DIRECT(HEX1_PIO_BASE, 0, seg7_encode((uint8_t)((value >> 4) & 0xFu)));
    IOWR_8DIRECT(HEX2_PIO_BASE, 0, seg7_encode((uint8_t)((value >> 8) & 0xFu)));
    IOWR_8DIRECT(HEX3_PIO_BASE, 0, seg7_encode((uint8_t)(status_bits & 0xFu)));
    IOWR_8DIRECT(HEX4_PIO_BASE, 0, 0xFFu);
    IOWR_8DIRECT(HEX5_PIO_BASE, 0, 0xFFu);
}

static uint32_t read_sample_stable(uint32_t base, uint32_t addr)
{
    ADC_SAMPLING_SET_READ_ADDR(base, addr);

    /* READ_DATA is associated with the buffered RAM read path. Read twice so
       the second read reflects the address just written. */
    (void)ADC_SAMPLING_READ_DATA(base);
    return ADC_SAMPLING_READ_DATA(base);
}

static uint32_t pack_scan_table(const uint8_t *seq, uint32_t len)
{
    uint32_t table = 0u;
    if (len > 6u) {
        len = 6u;
    }
    for (uint32_t i = 0; i < len; ++i) {
        table |= ((uint32_t)(seq[i] & 0x1Fu)) << (5u * i);
    }
    return table;
}

static double adc_code_to_volts(uint32_t chan, uint32_t code)
{
    static const double gain[6] = { 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 };
    static const int16_t offset[6] = { 0, 0, 0, 0, 0, 0 };

    double x = (double)(code & 0xFFFu);
    if (chan < 6u) {
        x = (x - (double)offset[chan]) * gain[chan];
    }
    return x * (TEST_VREF_VOLTS / 4095.0);
}

int main(void)
{
    uint32_t start_count;
    uint32_t end_count;
    uint32_t status;
    uint32_t trigger_index;
    uint32_t effective_end_count;
    unsigned int poll;
    uint8_t scan_seq[6] = { 1u, 2u, 3u, 4u, 5u, 6u };
    uint32_t scan_table;

    printf("\n=== ADC Sampling Controller Hardware Test ===\n");
    printf("Controller base : 0x%08X\n", (unsigned int)TEST_ADC_BASE);
    printf("JTAG UART base  : 0x%08X\n", (unsigned int)JTAG_UART_0_BASE);
    printf("On-chip RAM span: %u bytes\n", (unsigned int)ONCHIP_MEMORY2_0_SPAN);

    printf("\nResetting controller...\n");
    adc_sampling_stop(TEST_ADC_BASE);
    adc_sampling_soft_reset(TEST_ADC_BASE);
    alt_busy_sleep(1000);

    printf("Configuring controller: channel=%u prescaler=%u sample_period=%u\n",
           (unsigned int)TEST_ADC_CHANNEL,
           (unsigned int)TEST_PRESCALER_SEL,
           (unsigned int)TEST_SAMPLE_PERIOD);

    adc_sampling_configure(TEST_ADC_BASE,
                           TEST_SAMPLE_PERIOD,
                           TEST_ADC_CHANNEL,
                           TEST_PRESCALER_SEL);

    scan_table = pack_scan_table(scan_seq, TEST_SCAN_LEN);
    ADC_SAMPLING_WRITE_SCAN_TABLE(TEST_ADC_BASE, scan_table);
    ADC_SAMPLING_WRITE_SCAN_CTRL(TEST_ADC_BASE,
                                 (TEST_SCAN_ENABLE ? ADC_SAMPLING_SCAN_CTRL_ENABLE : 0u) |
                                 (TEST_SCAN_LEN & ADC_SAMPLING_SCAN_CTRL_LEN_MASK));

    ADC_SAMPLING_WRITE_TRIGGER_LEVEL(TEST_ADC_BASE, TEST_TRIGGER_LEVEL);
    ADC_SAMPLING_WRITE_TRIGGER_CHANNEL(TEST_ADC_BASE, TEST_TRIGGER_CHANNEL);
    ADC_SAMPLING_WRITE_PRE_TRIGGER_COUNT(TEST_ADC_BASE, TEST_PRE_TRIGGER_COUNT);
    ADC_SAMPLING_WRITE_POST_TRIGGER_COUNT(TEST_ADC_BASE, TEST_POST_TRIGGER_COUNT);
    ADC_SAMPLING_WRITE_TRIGGER_CFG(TEST_ADC_BASE,
                                   (TEST_TRIGGER_ENABLE ? ADC_SAMPLING_TRIGGER_CFG_ENABLE : 0u) |
                                   (TEST_TRIGGER_EDGE_FALLING ? ADC_SAMPLING_TRIGGER_CFG_EDGE_FALLING : 0u));

    start_count = ADC_SAMPLING_READ_SAMPLE_COUNT(TEST_ADC_BASE);
    status = ADC_SAMPLING_READ_STATUS(TEST_ADC_BASE);

    printf("Initial status     : 0x%08X\n", (unsigned int)status);
    printf("Initial sample cnt : %u\n", (unsigned int)start_count);
    printf("Scan              : enable=%u len=%u table=0x%08X\n",
           (unsigned int)TEST_SCAN_ENABLE,
           (unsigned int)TEST_SCAN_LEN,
           (unsigned int)scan_table);
    printf("Trigger            : enable=%u chan=%u level=%u edge=%s pre=%u post=%u\n",
           (unsigned int)TEST_TRIGGER_ENABLE,
           (unsigned int)TEST_TRIGGER_CHANNEL,
           (unsigned int)TEST_TRIGGER_LEVEL,
           (TEST_TRIGGER_EDGE_FALLING ? "falling" : "rising"),
           (unsigned int)TEST_PRE_TRIGGER_COUNT,
           (unsigned int)TEST_POST_TRIGGER_COUNT);

    hex_write(start_count, status);

    printf("\nArming capture...\n");
    {
        uint32_t control = ADC_SAMPLING_CONTROL_RUN_ENABLE;
        if (TEST_TRIGGER_ENABLE == 0u) {
            control |= ADC_SAMPLING_CONTROL_SINGLE_SHOT;
        }
        ADC_SAMPLING_WRITE_CONTROL(TEST_ADC_BASE, control);
    }

    end_count = start_count;
    for (poll = 0; poll < TEST_POLL_LIMIT; ++poll) {
        uint32_t display_count;
        alt_busy_sleep(10000);
        end_count = ADC_SAMPLING_READ_SAMPLE_COUNT(TEST_ADC_BASE);
        status = ADC_SAMPLING_READ_STATUS(TEST_ADC_BASE);
        display_count = end_count;
        if (((status & ADC_SAMPLING_STATUS_DONE) != 0u) && (display_count == 0u)) {
            display_count = 0x3FFu;
        }
        hex_write(display_count, status);
        if ((status & ADC_SAMPLING_STATUS_DONE) != 0u) {
            break;
        }
        if (((status & 1u) == 0u) && (end_count != start_count)) {
            break;
        }
    }

    status = ADC_SAMPLING_READ_STATUS(TEST_ADC_BASE);
    trigger_index = ADC_SAMPLING_READ_TRIGGER_INDEX(TEST_ADC_BASE);
    effective_end_count = end_count;
    if ((TEST_TRIGGER_ENABLE == 0u) &&
        ((status & ADC_SAMPLING_STATUS_DONE) != 0u) &&
        (effective_end_count == 0u)) {
        effective_end_count = TEST_BUFFER_DEPTH;
    }

    printf("Status after start : 0x%08X\n", (unsigned int)status);
    printf("Sample count       : %u\n", (unsigned int)effective_end_count);
    printf("Triggered          : %u\n", (unsigned int)((status & ADC_SAMPLING_STATUS_TRIGGERED) != 0u));
    printf("Trigger index      : %u\n", (unsigned int)trigger_index);

    if ((effective_end_count == start_count) &&
        ((status & ADC_SAMPLING_STATUS_DONE) == 0u)) {
        printf("\nTEST RESULT: FAIL\n");
        printf("Sample count did not change. Check:\n");
        printf("- FPGA is programmed with the current .sof\n");
        printf("- Nios software matches the current adc_c.sopcinfo/system.h\n");
        printf("- Modular ADC and controller are connected inside adc_c.qsys\n");
        printf("- Analog source is connected to the selected ADC channel\n");
        adc_sampling_stop(TEST_ADC_BASE);
        return 1;
    }

    printf("\nTEST RESULT: PASS\n");

    adc_sampling_stop(TEST_ADC_BASE);
    alt_busy_sleep(1000);

    {
        uint32_t dump_start = 0u;
        uint32_t dump_len = TEST_SAMPLE_DUMP;

        if ((status & ADC_SAMPLING_STATUS_TRIGGERED) != 0u) {
            dump_len = TEST_PRE_TRIGGER_COUNT + 1u + TEST_POST_TRIGGER_COUNT;
            if (dump_len > TEST_BUFFER_DEPTH) {
                dump_len = TEST_BUFFER_DEPTH;
            }
            dump_start = (trigger_index + TEST_BUFFER_DEPTH - (TEST_PRE_TRIGGER_COUNT % TEST_BUFFER_DEPTH)) % TEST_BUFFER_DEPTH;
        } else if ((status & ADC_SAMPLING_STATUS_DONE) != 0u) {
            dump_len = TEST_SAMPLE_DUMP;
            dump_start = 0u;
        }

        printf("CSV_BEGIN\n");
        printf("idx,addr,chan,code,volts\n");
        for (uint32_t i = 0; i < dump_len; ++i) {
            uint32_t addr = (dump_start + i) % TEST_BUFFER_DEPTH;
            uint32_t word = read_sample_stable(TEST_ADC_BASE, addr) & 0xFFFFu;
            uint32_t chan = (word >> 12) & 0xFu;
            uint32_t code = word & 0xFFFu;
            double volts = adc_code_to_volts(chan, code);
            printf("%u,%u,%u,%u,%.6f\n",
                   (unsigned int)i,
                   (unsigned int)addr,
                   (unsigned int)chan,
                   (unsigned int)code,
                   volts);
        }
        printf("CSV_END\n");
    }

    printf("\nIf the values change when you vary the analog input, the hardware path is working.\n");
    return 0;
}
