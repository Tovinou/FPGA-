# MAX 10 Digital Signal Processing and TinyML Demonstrator

A DE10-Lite / Intel MAX 10 FPGA reference design that demonstrates a complete embedded signal-processing pipeline:

```text
Analog input
    |
    v
MAX 10 Modular ADC
    |
    v
ADC Reader Avalon-MM master
    |
    v
Moving-average filter (VHDL)
    |
    v
ADC sample FIFO
    |
    v
Nios V/m processor
    |
    v
Fixed-point feature extraction and classifier (ai.c)
    |
    v
JTAG UART classification output
```

The design combines FPGA hardware DSP with processor-based TinyML-style inference. The current AI stage is a small deterministic fixed-point classifier intended for architecture demonstration and live bring-up. It is not yet a trained neural-network model.

## Project Status

The following functions have been verified on hardware:

- TIMER_HW_IP register, counting, compare, capture, PWM, and overflow tests
- Modular ADC sequencer access
- ADC continuous and one-shot mode selection
- LED and key PIO access
- ADC-to-moving-average-to-FIFO-to-Nios V data path
- 32-sample AI feature extraction and classification
- Nios V JTAG UART output
- Quartus timing closure for the configured 100 MHz SDRAM interface

The current live run reports:

```text
All hardware tests complete: 0 failure(s)
AI live demo: collecting 100 windows
```

## Hardware Architecture

### Clock domains

The board oscillator is 50 MHz. The Platform Designer PLL generates three relevant clocks:

| PLL output | Frequency | Phase | Consumers |
| --- | ---: | ---: | --- |
| `c0` | 10 MHz | 0 deg | ADC, Nios V, normal peripherals, DSP stream |
| `c1` | 100 MHz | 0 deg | Custom SDRAM controller |
| `c2` | 100 MHz | -30 deg | External `DRAM_CLK` forwarded to the SDRAM device |

The 10 MHz `c0` clock is intentional because it is required by the ADC configuration. The SDRAM controller is independent and uses `c1`; the SDRAM device receives the phase-shifted `c2` clock.

### ADC and DSP stream

The ADC reader obtains the configured sample-store data from the Modular ADC through Avalon-MM. It extracts the 12-bit CH0 sample and emits it through an Avalon-ST-style ready/valid interface.

The moving-average filter is configured as:

- 16 taps
- 12-bit input samples
- 16-bit output samples
- 20-bit accumulator
- Ready/valid streaming interface

The filter output is written into the 1024-entry ADC FIFO. Backpressure propagates upstream when the FIFO is full.

### ADC FIFO register interface

The FIFO is connected to the Nios V data manager at `ADC_FIFO_0_BASE`.

| Word offset | Byte offset | Function |
| ---: | ---: | --- |
| 0 | `0x00` | Read sample and pop one FIFO entry |
| 1 | `0x04` | Read status |
| 2 | `0x08` | Read sample count |
| 3 | `0x0C` | Write control |

The AI software checks the level register before reading a complete window. Empty data reads are therefore avoided.

### SDRAM

The custom controller in `ip/own_sdram` targets the onboard ISSI `IS42S16320D` SDRAM:

- 16-bit data bus
- 13-bit row/address bus
- 2-bit bank address
- 2 byte-mask signals
- 64 MiB Avalon-MM address span
- 100 MHz controller clock
- Phase-shifted 100 MHz external SDRAM clock

The external pins are exported by the top-level VHDL entity as `DRAM_*` signals and assigned in the Quartus `.qsf` file.

The SDC uses the datasheet timing values for the SDRAM control signals:

- Setup: 1.5 ns
- Hold: 0.8 ns

## AI Demonstration Architecture

The Nios V application reads 32 samples from the ADC FIFO for each inference window. `ai.c` computes three integer features:

1. **Energy:** normalized absolute distance from the ADC midpoint
2. **Variation:** normalized sum of sample-to-sample absolute differences
3. **Zero crossings:** number of sign transitions around the midpoint

These features are evaluated by a small fixed-point, four-output scoring model:

```text
Input features:  3
Output classes:  4
Arithmetic:      int16/int32
Window size:     32 samples
```

The current class labels are demonstration classes:

| Class | Intended interpretation |
| ---: | --- |
| 0 | Low or constant activity |
| 1 | Variation-dominant signal |
| 2 | Crossing-dominant signal |
| 3 | Energy and variation signal |

The weights are currently hand-selected. For meaningful classification, collect labeled feature data from known input signals and replace the demonstration weights with trained, quantized parameters.

## Repository Layout

```text
.
|-- Max10_Digital_signal_processing.qpf       Quartus project
|-- Max10_Digital_signal_processing.qsf       Device and pin assignments
|-- Max10_Digital_signal_processing.sdc       Timing constraints
|-- Max10_Digital_signal_processing_top.vhd   FPGA top-level entity
|-- Max10_embedded_sys.qsys                   Platform Designer system
|-- Max10_embedded_sys/                       Generated Platform Designer sources
|-- ip/
|   |-- ADC_FIFO/                             ADC output FIFO
|   |-- ADC_Reader/                           ADC sample-store reader
|   |-- Moving_average/                       Moving-average IP package
|   |-- Timer_HW_ip/                          Custom timer IP
|   `-- own_sdram/                            Custom SDRAM controller
|-- software/
|   |-- app/                                  Nios V application and tests
|   `-- hal_bsp/                              Generated HAL BSP
`-- build/                                    CMake build directory
```

Important application files:

- `software/app/src/main.c` - test and AI demo entry point
- `software/app/src/ai.c` - FIFO window reader, features, and classifier
- `software/app/src/ai.h` - AI application interface
- `software/app/src/timer_hw_ip_test.c` - timer hardware tests
- `software/app/src/adc_test.c` - ADC sequencer tests
- `software/app/src/pio_led_test.c` - LED and key tests

## Software Build

The software uses the Intel Nios V RISC-V cross-toolchain and CMake. The configured build directory is already associated with the generated HAL BSP.

From PowerShell:

```powershell
$env:Path = "C:\altera_lite\25.1std\niosv\bin;$env:Path"
cmake --build build --parallel 4
```

The build generates:

```text
build/app.elf
build/app.elf.objdump
build/sram.hex
```

The stack report is printed during the build. The current application occupies approximately 103 KiB and has more than 65 MiB available in the SDRAM address space for runtime stack and heap according to the Nios V stack-report tool.

## FPGA Programming and Application Download

1. Compile and fit the Quartus project.
2. Program the MAX 10 with the generated `.sof` file.
3. Start the JTAG UART terminal in one shell:

```powershell
& "C:\quartus\bin64\juart-terminal.exe"
```

4. In a second Nios V Shell, download and run the application:

```cmd
"C:\altera_lite\25.1std\niosv\bin\niosv-download.exe" -g "C:/projects/Max10_Digital_signal_processing/build/app.elf"
```

Use forward slashes in the ELF path. The `-g` option resumes the Nios V after download. Keep `juart-terminal` running to see the test and AI output.

## Demonstrating the ADC Input

Use a passive analog source such as a `10 kOhm` linear potentiometer or a function generator. Connect the source ground to the DE10-Lite ground and keep the ADC input within the voltage range specified by the DE10-Lite documentation.

For a function generator, begin conservatively with:

```text
Waveform: sine
Frequency: 100 Hz
Offset: 1.25 V
Amplitude: 1.0 Vpp
```

A constant input produces values similar to:

```text
energy=256 variation=0 crossings=0 class=0
```

A changing waveform should produce nonzero variation and zero-crossing values. Use known signal conditions to collect data before interpreting the four demonstration classes.

Do not guess the physical ADC connector pin. Confirm the CH0 connection in the DE10-Lite board documentation or schematic before applying an external signal.

## Timing Validation

The timing constraints are in `Max10_Digital_signal_processing.sdc`. The expected timing arrangement is:

```text
c0: 10 MHz, 0 deg
c1: 100 MHz, 0 deg
c2: 100 MHz, -30 deg
```

Run Quartus TimeQuest after regenerating Platform Designer output. Sign-off requires positive setup and hold slack for all required corners. The `DRAM_CLK` forwarded-clock output may appear as an unconstrained output in the generic output-port report; the relevant SDRAM control paths are checked against the phase-shifted clock using the datasheet output-delay constraints.

## Limitations and Next Steps

- The current AI classifier is a hand-tuned demonstration model, not a trained neural network.
- The ADC FIFO sample-store path should be characterized with labeled input data.
- The AI demo currently processes a finite number of windows and prints results through JTAG UART.
- A production TinyML version could replace the scoring model with quantized neural-network weights or LiteRT for Microcontrollers after model training and runtime integration.
- Hardware validation should include signal-frequency sweeps, noise tests, ADC range checks, and long-duration SDRAM traffic tests.
