FPGA Projects

This repository contains a collection of FPGA development projects, primarily for Xilinx Vivado.
Each project demonstrates specific digital design concepts, IP integration, or complete FPGA-based systems.

📁 Repository Structure

- `Accelerometer/` – ADXL345 SPI accelerometer demo with VGA output components
- `basic_gate/` – Basic combinational logic gate examples with VHDL testbench
- `comparator/` – Simple comparator module and simulation assets
- `complex_logic_circuit/` – Composite logic (includes priority encoder) with testbench
- `ethernet/` – Vivado project (`ethernet.xpr`) featuring AXI Ethernet and MicroBlaze system
- `fso_satcom/` – Free-space optical satcom HDL modules and top-level integration
- `full_adder/` – Full and half-adder modules with simulation

🧰 Tools & Requirements

- `Vivado Design Suite` (version varies by project)
- Quartus Prime Lite Edition (Cyclone V/MAX10)
- Optional: `ModelSim/Questa`, `Vivado Simulator`, or `Verilator` for simulation
- Supported boards depend on each project (e.g., Basys 3, Nexys A7, Zybo Z7, MAX10). Refer to the project folder README when available.

🚀 Getting Started

Clone the repository

```
git clone <repo-url>
cd <repo-folder>
```

Open a project

- Choose a folder from the repository structure above
- If the folder contains a `.xpr` file (e.g., `ethernet/ethernet.xpr`), open it directly in Vivado
- Otherwise, create a new Vivado project and add sources from `sources_1/new` and testbenches from `sim_1/new` when present
- Regenerate IP cores if prompted
- Run synthesis, implementation, and program your FPGA board

📚 Project Contents

Typical project folders include:

- Design description and, where available, a project-specific README
- Block diagrams, images, or schematics (e.g., `Accelerometer/images/`)
- Simulation files and testbenches (usually under `*/sim_1/new/`)
- Source code in VHDL/Verilog/SystemVerilog (usually under `*/sources_1/new/`)
- TCL scripts or Vivado project files (`*.xpr`) when applicable

🧪 Simulation

Some projects include testbenches compatible with:

- ModelSim / Questa
- Vivado Simulator
- Verilator

Run simulation using the tool of your choice by pointing to files under `sim_1/new` and `sources_1/new`.

📝 Contributing

Contributions are welcome!
You can add:

- New FPGA projects
- Improvements to existing designs
- Documentation or diagrams
- Board support packages

Please open an issue or pull request before large changes.

📄 License

Specify your license here, e.g.:

MIT License
