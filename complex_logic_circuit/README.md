Complex Logic Circuit System
Overview
The Complex Logic Circuit is a versatile digital design that performs multiple arithmetic, logic, and comparison operations on 4-bit inputs. It features various output modes, status flags, and advanced functions like parity calculation and leading zero counting.

Features
Basic Operations
Bitwise AND, OR, XOR operations

NOT operation on input A

Arithmetic Operations
4-bit addition with 5-bit output to handle overflow

4-bit subtraction with underflow detection

Comparison Operations
Equality check between inputs A and B

Greater-than comparisons (A > B, B > A)

Advanced Functions
Even parity calculation for input A

Leading zeros count in input A (using a priority encoder)

Mode-based output multiplexing

Status Flags
Overflow detection for addition

Underflow detection for subtraction

Valid output indicator (tied to enable signal)

Design Architecture
Entity: complex_logic_circuit
Inputs
a, b: 4-bit input vectors

enable: Active-high enable signal

mode_sel: 2-bit mode selection for output multiplexer

Outputs
Basic logic outputs: out_and, out_or, out_xor, out_not_a (single bits from MSB of operations)

Arithmetic outputs: sum (5-bit), difference (4-bit)

Comparison outputs: equal, a_greater, b_greater

Advanced outputs: parity_a, leading_zeros (3-bit)

Multiplexed output: mux_out (4-bit)

Status flags: overflow, underflow, valid

Component: priority_encoder
Encodes the position of the first '1' in a 4-bit input

Outputs the count of leading zeros as a 3-bit binary number

Includes a valid output signal that indicates if at least one '1' is present

Testbench: complex_logic_circuit_tb
The testbench comprehensively verifies all functionality of the complex logic circuit:

Test Cases
Disabled State: Verifies all outputs are zero when enable is low

Basic Logic Operations: Tests AND, OR, XOR, and NOT functions

Arithmetic Operations: Verifies addition and subtraction

Overflow Test: Checks overflow detection in addition

Underflow Test: Checks underflow detection in subtraction

Equality Test: Verifies the equality comparator

Leading Zeros Test: Tests the priority encoder with various input patterns

Parity Test: Verifies even parity calculation

Multiplexer Test: Cycles through all output modes

Edge Cases: Tests with all zeros and all ones inputs

Disable/Enable Test: Verifies proper enable/disable functionality

Monitoring
The testbench includes a monitor process that reports key signals and results during simulation, making it easy to verify correct operation.

Usage
Simulation
Compile the VHDL files using a VHDL simulator (e.g., ModelSim, GHDL)

Run the testbench to verify functionality

Observe the report statements for test results

Synthesis
The design is suitable for synthesis to FPGA or ASIC targets. Key considerations:

The design uses standard logic operations that map well to FPGA resources

The priority encoder is implemented efficiently with a case statement

Arithmetic operations use resize functions for proper bit-width handling

File Structure
text
complex_logic_circuit/
├── complex_logic_circuit.vhd      # Main design file
├── complex_logic_circuit_tb.vhd   # Testbench file
└── README.md                      # This file
Design Notes
All outputs are gated by the enable signal; when disabled, outputs are forced to zero

The multiplexed output (mux_out) selects between the four basic logic operations based on mode_sel

The priority encoder component is instantiated and used for leading zero counting

Arithmetic operations use unsigned arithmetic for consistent behavior

Status flags provide information about arithmetic operation results

Expected Results
When running the testbench, you should see:

All tests passing with appropriate report messages

Correct arithmetic results for addition and subtraction

Proper detection of overflow and underflow conditions

Accurate leading zero counts and parity calculations

Correct multiplexer operation based on mode selection

This design demonstrates a comprehensive digital logic system with multiple operational modes and status reporting, suitable as a learning example or as a component in larger digital systems.