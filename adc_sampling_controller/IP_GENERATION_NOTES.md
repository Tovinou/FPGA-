# IP Generation Notes — Altera Modular ADC Core

The MAX 10's analog-to-digital converter is a **hardened block**, not raw
fabric logic. You cannot write its silicon driver in plain VHDL the way you
can with the timer IP — Intel/Altera requires it to be accessed through a
**generated IP core** (Modular ADC or Modular Dual ADC) produced by the
Quartus Prime IP Catalog. This project's RTL (`ADC_SAMPLING_CONTROLLER_HW_IP`,
`adc_trigger_engine`) is written to bind directly to that generated core's
standard interface, so once you generate it as described below, no source
changes are needed.

## 1. Why ADC1 only

On the DE10-Lite, the MAX 10 device has two ADC blocks (ADC1, ADC2), but only
**ADC1 is wired out to board pins** — six analog channels on the Arduino Uno
header (`ADC1_IN1`..`ADC1_IN6`, mapped to Arduino `A0`..`A5`). ADC2 exists on
the die but has no external pin connections on this board, so only the
**single-ADC "Modular ADC" core** (not "Modular Dual ADC") is relevant here.

## 2. Generating the core in Quartus Prime

1. Open your DE10-Lite Quartus project (device `10M50DAF484C7G`).
2. **Tools → IP Catalog**.
3. Search for **"ADC"**. Select **Modular ADC Core** (Library: Interfaces →
   ADC) and click **Add...**.
4. Name the instance `modular_adc_0` (matches the component name already
   used in `DE10_LITE_ADC_SAMPLING_TOP.vhd` — keep this name, or update the
   `component modular_adc_0` declaration in the top level if you rename it).
5. In the parameter editor:
   - **Number of ADCs**: 1 (single ADC mode — ADC1 only, matching the
     DE10-Lite's wiring).
   - **Sequencer mode**: User Logic (so commands are issued externally by
     this project's trigger engine, rather than a fixed auto-sequence) —
     some Quartus versions label this "Command/response Avalon-ST"; pick
     whichever option exposes `command_*` / `response_*` ports rather than
     a fixed-sequence-only mode, since the trigger engine needs to choose
     the channel per-conversion.
   - **Clock**: the core's internal ADC clock divider must bring the input
     clock down to the ADC's required ~10 MHz-class internal rate — refer
     to the parameter editor's clock-divider field and set it for whichever
     clock you feed `clock_clk` (50 MHz from `MAX10_CLK1_50` in this
     project's top level).
   - **Channels enabled**: enable at least `ADC1_IN1` (Arduino `A0`); enable
     more if you plan to scan multiple analog inputs (the trigger engine's
     `adc_channel_sel` register selects which one is requested on each
     trigger).
6. Click **Generate HDL**, choose **VHDL**, and finish. Quartus places the
   generated wrapper (e.g. `modular_adc_0.vhd` plus supporting files) in your
   project's IP directory — add it to your project file list alongside this
   project's RTL.

## 3. Confirming the generated port names

Different Quartus versions have very slightly different naming for the
clock/reset pair on generated IP (some show `clock_clk` /
`clk_clock_reset_reset`, others a plain `clk` / `reset`). **After
generating**, open the generated `modular_adc_0.vhd` (or the `.cmp`/`.bsf`
symbol file) and compare its entity port list against the
`component modular_adc_0` declaration near the top of
`DE10_LITE_ADC_SAMPLING_TOP.vhd`. If your Quartus version generated different
port names, edit only that one component declaration to match — the rest of
the design (the sampling controller, the timer-driven trigger engine, the
sample buffer) is unaffected, since it talks to the ADC purely through the
standard `command_valid/command_ready` and `response_valid/response_data`
Avalon-ST signals, which are the same across Quartus versions.

The command/response port shapes used throughout this project come directly
from Intel's documented Modular ADC control core interface: `command_valid`,
`command_channel[4:0]`, `command_startofpacket`, `command_endofpacket`,
`command_ready`, `response_valid`, `response_channel[4:0]`,
`response_data[11:0]`, `response_startofpacket`, `response_endofpacket`. The
ADC data path is fixed at 12-bit resolution and the channel field is 5 bits
wide (supports up to 32 sequencer slots), which is why
`ADC_SAMPLING_CONTROLLER_HW_IP` and `adc_trigger_engine` default their
`ADC_DATA_WIDTH` / `ADC_CHAN_WIDTH` generics to 12 and 5.

## 4. Timing / sample-rate ceiling

The Modular ADC core's own internal conversion latency (clock cycles per
sample, dictated by its internal clock divider and a fixed minimum
conversion time per the MAX 10 ADC hard IP) sets the real ceiling on how
fast you can usefully trigger it — driving `sample_period` faster than the
ADC core can physically convert will just cause requests to queue up against
`command_ready` (the trigger engine already respects this back-pressure: see
`adc_trigger_engine.vhd`, `cmd_proc`). Check the parameter editor's reported
"maximum sample rate" for your chosen clock-divider setting and pick
`sample_period` (in `ADC_SAMPLING_CONTROLLER_HW_IP` register `0x3`) no
smaller than that, in ticks of whatever `prescaler_sel` you've chosen. For
true ~1 Msps burst capture, prescaler should stay at `000` (divide-by-1, full
50 MHz tick resolution) and `sample_period` should be set to whatever tick
count corresponds to the ADC core's actual minimum conversion time.

## 5. Simulation note

Since the ADC core is a generated, technology-specific IP wrapper around a
hard block, it will not simulate bit-accurately in a plain RTL simulator
without Quartus-provided simulation libraries on your `PATH`/library
mapping. Per your earlier preference, this project ships without a
testbench; if you add one later, instantiate the generated
`modular_adc_0` core's IP-provided simulation model (Quartus generates this
alongside the synthesis model) rather than this project's own files when
simulating the ADC response side.
