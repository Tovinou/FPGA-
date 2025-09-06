# Free Space Optical Satellite Communication System

## Project Overview

- **Title**: Free Space Optical Satellite Communication System
- **Author**: FPGA Engineer Komlan Tovinou
- **Target Platform**: Intel MAX10 DE10-Lite FPGA Board (Device: 10M50DAF484C7G)
- **Date**: September 2025
- **Purpose**: This project implements a Free Space Optical (FSO) communication system on an Intel MAX10 FPGA. It demonstrates a complete optical data transmission pipeline, including data generation, error correction coding, serialization/deserialization, optical modulation, and link status monitoring. The system is controlled via onboard switches and provides real-time feedback on LEDs and 7-segment displays.

## System Architecture

The system is a modular VHDL design with a top-level entity (`fso_satcom_top`) that integrates all components. The architecture is divided into a transmit path, a receive path, and a central control system.

### Core Components

- **`system_control_fsm`**: A finite state machine that manages the overall system state, transitioning from pointing and link setup to active data transmission based on hardware signals.
- **`pll_clocks`**: Generates 25 MHz and 1 MHz clocks from the main 50 MHz system clock.
- **`test_data_generator`**: Produces a 32-bit test data pattern for transmission.
- **`error_correction_codec`**: Adds an 8-bit parity code to the 32-bit data on the transmit path and performs error detection/correction on the receive path.
- **`serializer`**: Converts the 40-bit parallel data (32-bit data + 8-bit parity) into a serial stream for transmission.
- **`deserializer`**: Converts the received serial stream back into 40-bit parallel data.
- **`optical_modulator`**: Modulates the serial data onto an optical signal for the laser transmitter.
- **`frame_sync`**: Synchronizes to the incoming serial data stream to identify frame boundaries.
- **`link_monitor`**: Monitors the quality of the received signal, calculating bit error rate and link quality score.
- **`pointing_control`**: Manages the azimuth and elevation controls for optical antenna pointing (stubbed in this implementation).
- **`debouncer` / `synchronizer`**: Conditions the push-button and switch inputs to prevent metastability.
- **`seven_segment_decoder`**: Displays status information (link quality, BER, received data) on the 7-segment displays.

### Data Flow

**1. Transmit Path:**
- The `test_data_generator` creates a 32-bit word.
- The `error_correction_codec` computes and appends an 8-bit parity code, creating a 40-bit frame.
- The `serializer` converts this 40-bit frame into a serial stream.
- The `optical_modulator` drives an external laser (`GPIO_OUT(0)`) with this serial data.

**2. Receive Path:**
- A serial data stream is received from an optical sensor via `GPIO_IN`.
- The `frame_sync` module locks onto the data stream to detect valid frames.
- The `deserializer` converts the serial data back into 40-bit parallel data.
- The `error_correction_codec` checks the parity bits, detects and corrects single-bit errors, and outputs the corrected 32-bit data.
- The `link_monitor` analyzes the received data to provide real-time link quality metrics.

## System States

The `system_control_fsm` governs the system's operation through the following states:

- **`IDLE`**: The system is waiting for the `system_enable` signal and for the PLL to lock.
- **`POINTING`**: The system waits for the `pointing_stable` and `tracking_lock` signals, indicating alignment is complete.
- **`LINK_SETUP`**: The system attempts to synchronize with the incoming data stream (`rx_frame_sync`).
- **`TRANSMITTING`**: The link is established, and data is actively being transmitted and received. The system monitors `link_quality` and will move to `ERROR_STATE` if it degrades.
- **`ERROR_STATE`**: Entered if the link quality is poor. The system will attempt to re-establish the link by returning to `POINTING` or `TRANSMITTING` if the quality improves.

## Controls and Interfaces

The system is controlled using the slide switches (`SW`) and push-buttons (`KEY`) on the DE10-Lite board.

- **`SW(9)`**: System Reset (active low). Set to '1' for normal operation.
- **`SW(8)`**: Laser Power Control. '1' enables manual power control via `SW(7:0)`. '0' sets a default power level.
- **`SW(7:0)`**: Manual Laser Power Level (when `SW(8)` is '1').
- **`SW(3)`**: Transmit Data Valid. Enables the flow of data from the test generator.
- **`SW(2:0)`**: Display Mode. Selects the information shown on the `LEDR` and 7-segment displays:
    - `001`: Link Quality
    - `010`: Bit Error Rate
    - `011`: Received Data
    - `100`: Error Correction Status
    - `other`: Debug Signals
- **`KEY(1)`**: System Enable.
- **`KEY(0)`**: Tracking Lock (used for pointing).

## FPGA Implementation Summary

- **Family**: MAX 10
- **Device**: 10M50DAF484C7G
- **Total logic elements**: 7,066
- **Total registers**: 766
- **Total pins**: 101
- **Total memory bits**: 0
- **Embedded Multiplier 9-bit elements**: 0
- **Total PLLs**: 0

## How to Build and Simulate

This is an Intel Quartus Prime project.

- **To Build**: Open `fso_satcom_top.qpf` in Quartus Prime and run the compiler.
- **To Simulate**: The simulation is configured for ModelSim. The testbench file is located at `simulation/modelsim/fso_satcom_top.vht`.
