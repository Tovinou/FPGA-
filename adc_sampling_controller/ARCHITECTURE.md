# ADC Sampling Controller Architecture

## Goal

Build a reusable MAX 10 ADC sampling controller for the DE10-Lite where a hardware timer generates deterministic ADC conversion requests and returned 12-bit samples are stored in an on-chip circular buffer for Avalon-MM readback.

In the current project, the integration is done in the Platform Designer system [`adc_c.qsys`](adc_sampling_controller/adc_c.qsys). The board-level top entity [`DE10_LITE_ADC_SAMPLING_TOP`](adc_sampling_controller/DE10_LITE_ADC_SAMPLING_TOP.vhd) only wraps `adc_c` and exposes a few signals to LEDs/headers.

## System-level blocks (`adc_c.qsys`)

`adc_c` contains:

- `adc_sampling_controller_hw_ip_0` (custom component from `ip/ADC_Sampling_Controller_HW_ip`)
- `modular_adc_0` (Intel Modular ADC control core)
- `intel_niosv_m_0` (Nios V/m)
- `altpll_0` (PLL)
- `jtag_uart_0` (console/communication)
- `onchip_memory2_0` (on-chip RAM)

Key connections inside `adc_c`:

- `adc_sampling_controller_hw_ip_0.adc_command` → `modular_adc_0.command`
- `modular_adc_0.response` → `adc_sampling_controller_hw_ip_0.adc_response`

## Board wrapper (`DE10_LITE_ADC_SAMPLING_TOP.vhd`)

The top-level entity instantiates only:

- `adc_c` (the generated Platform Designer system)
- `seg7_decoder` (used only for displaying switch values)

The exported conduit `adc_sampling_controller_hw_ip_0_sample_marker_conduit` is routed to `LEDR(0)` and `ARDUINO_IO(0)` for probing.

## Custom component internals

### `ADC_SAMPLING_CONTROLLER_HW_IP`

Avalon-MM register wrapper plus glue logic. It exposes:

- control/status registers
- readback of the circular sample buffer (`READ_ADDR` / `READ_DATA`)
- `capture_done_int` pulse for single-shot completion (suitable to connect to a CPU IRQ)
- Avalon-ST command/response ports for the Modular ADC control core

### `adc_trigger_engine`

Sampling datapath. It reuses the timer block for sample cadence, converts timer compare pulses into Modular ADC command beats, captures ADC responses into RAM, and reports trigger-to-response latency through the timer capture path.

`SAMPLE_PERIOD` is the software-visible period in prescaled ticks. Internally, the engine feeds `SAMPLE_PERIOD - 1` to the timer comparator because the counter starts at zero.

### `sample_buffer`

Single-clock dual-port RAM with independent write and read addresses. The write side is driven by ADC responses. The read side is driven by the register wrapper.

RAM is intentionally not power-up initialized to avoid MAX 10 Assembler error (14703) in Internal Configuration mode.

### Reused timer IP

The controller reuses these timer modules (packaged together with the controller RTL):

- `timer_prescaler`: divides the system clock
- `timer_counter`: free-running counter
- `timer_comparator`: conversion trigger pulse generation
- `timer_capture`: response latency measurement
- `timer_pwm`: sample marker generation

## Register map (`adc_sampling_controller_hw_ip_0`, word address)

| Word | Name | Access | Bits |
| ---- | ---- | ------ | ---- |
| `0x0` | `CONTROL` | R/W | `[0]` run enable, `[1]` single shot, `[2]` soft reset |
| `0x1` | `PRESCALER_SEL` | R/W | `[2:0]` timer prescaler |
| `0x2` | `ADC_CHANNEL_SEL` | R/W | `[4:0]` Modular ADC channel |
| `0x3` | `SAMPLE_PERIOD` | R/W | Prescaled ticks between trigger requests |
| `0x4` | `STATUS` | R/O | `[0]` busy, `[1]` overflow, `[2]` single-shot done |
| `0x5` | `SAMPLE_COUNT` | R/O | Current write pointer |
| `0x6` | `TRIGGER_LATENCY` | R/O | Timer ticks from trigger to ADC response |
| `0x7` | `READ_ADDR` | R/W | Sample buffer read address |
| `0x8` | `READ_DATA` | R/O | Sample buffer data for `READ_ADDR` |

## Packaging / generation

`ip/ADC_Sampling_Controller_HW_ip` contains the self-contained Platform Designer component:

- `adc_sampling_controller_hw_ip_hw.tcl` (hardware component metadata)
- `adc_sampling_controller_hw_ip_sw.tcl` (HAL driver metadata)
- `HAL/inc/adc_sampling_controller_hw_ip.h` (C helpers)
- `HDL/*.vhd` (controller RTL plus timer dependencies)

The `ip/components.ipx` file provides a local component index so command-line generation tools can discover packaged components under `ip/`.
