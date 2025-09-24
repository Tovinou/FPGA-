# Basic Gate Vivado Project

This repository contains a basic digital logic gate implemented in VHDL, designed and managed using Xilinx Vivado.

## Project Structure

*   `basic_gate.vhd`: The VHDL source code for the basic gate.
*   `basic_gate_tb.vhd`: The VHDL testbench for simulating the `basic_gate` module.
*   `basic_gate.xpr`: The main Vivado project file.
*   `basic_gate.srcs/`: Contains all source files (VHDL, constraints, etc.).
*   `basic_gate.sim/`: Contains simulation-related files.
*   `basic_gate.runs/`: Contains synthesis, implementation, and bitstream generation run data.

## Getting Started

To open and work with this project:

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/Tovinou/FPGA-.git
    cd basic_gate
    ```
2.  **Open in Vivado:**
    Launch Xilinx Vivado and open the project file `basic_gate.xpr`.

## Design Details

The `basic_gate.vhd` file implements a simple logic gate. You can inspect the VHDL code to understand its functionality.

## Simulation

The `basic_gate_tb.vhd` file provides a testbench to verify the functionality of the `basic_gate`.
To run the simulation in Vivado:
1.  In the Vivado Flow Navigator, click on `Run Simulation -> Run Behavioral Simulation`.
2.  Observe the waveforms to verify the gate's behavior.

## Synthesis and Implementation

You can synthesize and implement the design using the Vivado tools to target a specific FPGA device.
1.  In the Vivado Flow Navigator, click on `Run Synthesis`.
2.  After synthesis, click on `Run Implementation`.
3.  Finally, `Generate Bitstream` to create the programming file for your FPGA.

---