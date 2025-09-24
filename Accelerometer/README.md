FPGA-based Accelerometer with VGA Display

This project implements an SPI master unit on an FPGA to enable communication with up to four slave devices simultaneously. The system supports configurable transfer modes, provides error handling, and complies with industrial standards for the SPI communication protocol. The primary goal is to measure acceleration in three axes (X, Y, Z) using an ADXL345 accelerometer and display the data graphically on a VGA screen and numerically on 7-segment displays in real-time. This document outlines the development environment, VHDL implementation, verification, validation, and analysis.
Background
The purpose of this project is to develop a system capable of measuring acceleration in three axes and presenting this data visually on a VGA display. By leveraging an FPGA (Field-Programmable Gate Array), the system achieves high performance and flexibility for handling parallel processes, making it ideal for real-time applications. Accelerometers, such as the ADXL345, are widely used in applications ranging from smartphones and gaming consoles to automotive and aerospace systems, providing critical data for navigation, stabilization, and control.


Design Description
The system integrates an ADXL345 accelerometer communicating via an SPI bus with an FPGA-based system. The accelerometer measures acceleration in three axes (X, Y, Z), which is processed and displayed on a VGA screen and 7-segment displays in real-time. See the ADXL345 datasheet for details.
System Architecture
The system architecture includes:

accelerometer_adxl345: Configures and reads data from the ADXL345 accelerometer via SPI.
metastability: Ensures stable reset and SPI clock signals.
spi_master: Manages SPI communication with the accelerometer.
VGA_komponent: Generates VGA signals for display output, including an integrated PLL.
data_interface: Links accelerometer data to the VGA component.
Accel_Display: Converts accelerometer data for 7-segment display output.

The architecture synchronizes asynchronous inputs in the top-level acc_top_sys file, with an integrated PLL for VGA timing.
Subsystems
![alt text](image.png)
![alt text](image-1.png)
![alt text](image-2.png)
Accelerometer_adxl345: Manages SPI communication with the ADXL345, using a state machine for operation sequencing. Generic parameter: d_width (default 16 bits).
Metastability: Stabilizes reset signals to prevent metastability issues.
Spi_master: Handles SPI communication with configurable clock polarity and phase. Generic parameter: d_width (default 16 bits).
VGA_komponent: Generates VGA signals, incorporating a PLL for 25 MHz clock generation, DPRAM for image data storage, and VGA_Sync for timing and color signals.
Data_interface: Processes accelerometer data for VGA and 7-segment display.
Accel_Display: Formats acceleration data for 7-segment display output.
![alt text](image-3.png)
![alt text](image-4.png)

Subsystem of Subsystem
The VGA component includes:

PLL: Generates a 25 MHz clock from a 50 MHz input for VGA timing.
DPRAM: Stores image data, supporting simultaneous read/write operations.
VGA_Sync: Generates horizontal/vertical sync signals and RGB colors based on DPRAM data.


Tool Settings and Assignments
The design uses Quartus 18.1 with the following settings:

Simulation: Added testbench in EDA Tool Settings.
Timing Analysis: Added acc_top_sys.sdc, enabled worst-case path reporting.
Power Analysis: Enabled power analysis with 12.5% toggle rate.

Verification
Verification results from ModelSim confirmed the test protocol outcomes, ensuring correct SPI communication, accelerometer initialization, and VGA/7-segment outputs.

The design is resource-efficient, using minimal logic elements, registers, and memory. Power consumption is low due to limited resource usage and a single PLL.
Optimization
Optimization was performed using Quartus Resource Optimization Advisor:

Enabled shift register merging.
Configured clock topology analysis and fitter effort for reduced compilation time.

Validation
Validation was performed on a DE10-Lite FPGA board connected to a VGA screen. The system displayed:

X-axis: Red rectangle (x: 0-360, y: 0-320).
Y-axis: Green rectangle (x: 0-410, y: 280-480).
Z-axis: Blue rectangle (x: 300-640, y: 240-480).
7-segment displays showed "000" when no acceleration was detected.

Conclusion
The acc_top_sys VHDL design successfully integrates an ADXL345 accelerometer with a VGA display and 7-segment displays on an Altera FPGA using Quartus 18.1 and ModelSim. The design is resource-efficient but has minor issues (e.g., warnings) that need addressing. Future optimizations could improve signal handling and performance with advanced licenses.

Appendix B: Testbench
-- Clock generation process
PROCESS
BEGIN
    while now < 5000 ns loop -- Simulate for 5000 ns
        clock_50 <= '0';
        wait for CLK_PERIOD;
        clock_50 <= '1';
        wait for CLK_PERIOD;
    end loop;
    wait;
END PROCESS;

-- Stimulus process
stim_proc: PROCESS
BEGIN
    -- Reset activated
    reset_n <= '0';
    wait for 100 ns;
    -- Release reset
    reset_n <= '1';
    wait for 100 ns;
    wait for 1000 ns; -- Wait for 500 ns   
    WAIT;                                                        
END PROCESS;      

-- Verification of Stimulus process
process
begin
    -- Test case 1
    miso <= '1';
    wait for 100 ns;
    miso <= '0';
    
    -- Test case 2
    wait for 100 ns;
    miso <= '1';
    wait for 100 ns;
    miso <= '0';
    
    -- Test case 3
    wait for 100 ns;
    miso <= '1';
    wait for 100 ns;
    miso <= '0';
    
    wait;
end process;
