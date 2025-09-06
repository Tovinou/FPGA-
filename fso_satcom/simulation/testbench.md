Testbench Details

Clock Generation:

Generates a 50 MHz clock (CLK_PERIOD = 20 ns) for MAX10_CLK1_50.
Runs continuously until sim_done is true.


Stimulus Process:

Reset: Asserts SW(9) low for 10 cycles, then deasserts.
System Enable: Simulates KEY[1] press (active-low) for 1 ms to pass debouncer, enabling system_enable via sync_out(1).
Laser Power: Sets SW(8) = '1' and SW(7:0) = x"FF" for maximum laser power.
Data Transmission: Enables SW(3) for tx_data_valid.
Display Modes: Cycles through SW(2:0) = "001", "010", "011", "100" to test link_quality, bit_error_rate, rx_data_out, and rx_error_corrected on LEDR and HEX0–HEX5.
Serial Data: Uses send_serial_data to simulate 40-bit frames on GPIO(1) (optical_rx_data):

Valid data: x"1234567890".
Corrupted data: x"12345678FF" (to trigger rx_error_detected or rx_error_corrected).
Data is sent at 1 MHz rate (40 cycles at 25 MHz to simulate clk_1mhz).




Monitor Process:

Reports changes in LEDR, HEX0–HEX5, and GPIO(0) (optical_tx_data) every 100 cycles.
Uses to_string for readable output in ModelSim.


Assumptions:

error_correction_codec decodes 40-bit rx_decoded_data and sets rx_error_corrected for correctable errors.
pointing_control_max10 sets pointing_stable after a delay, allowing system_ready to activate displays.
frame_sync validates frames based on FRAME_SIZE = 1024.
pll_clocks generates clk_25mhz and clk_1mhz with pll_locked.




Expected Behavior

Reset Phase: All outputs (LEDR, HEX0–HEX5, GPIO) should be inactive.
System Enable: After KEY[1] press, system_ready and link_established should activate (assuming pll_locked and pointing_stable).
Display Modes:

"001": LEDR shows link_quality & "00", HEX0–HEX5 show link_quality & bit_error_rate.
"010": LEDR shows bit_error_rate(9:0), HEX0–HEX5 show bit_error_rate & link_quality.
"011": LEDR shows rx_data_out(9:0), HEX0–HEX5 show rx_data_out(23:0).
"100": LEDR(0) and HEX5 show rx_error_corrected.


Serial Data:

Valid frame (x"1234567890") should produce rx_data_out matching the lower 32 bits (x"12345678") and rx_data_valid = '1'.
Corrupted frame (x"12345678FF") should trigger rx_error_detected or rx_error_corrected.


GPIO Outputs: GPIO(0) (optical TX), GPIO(2) (laser enable), GPIO(10:3) (laser power), GPIO(26:11) (azimuth), and GPIO(35:27) (elevation) should reflect system state.


Simulation Setup

Compile in ModelSim:

Compile fso_satcom_top.vhd (artifact_id="b754ff3e-2475-419a-9c51-de8058c60310").
Compile error_correction_codec.vhd (artifact_id="fa166b69-bc4a-45aa-ae00-c852386c42c1").
Compile pointing_control_max10.vhd (artifact_version_id="f4874e31-5fb5-4000-9332-d3696292dd64").
Compile other components (frame_sync, optical_modulator, link_monitor, pll_clocks, debug_counters, deserializer, serializer, system_control_fsm, seven_segment_decoder, debouncer, synchronizer, test_data_generator) if available, or stub them with empty architectures.
Compile fso_satcom_top_tb.vhd (artifact_id="d4f7e8a2-3c4b-4a1f-9e2d-5f8c7a9b3e45").
Example stub for missing components:
vhdlentity frame_sync is
    generic (FRAME_SIZE : integer := 1024);
    port (
        clk              : in  std_logic;
        rst_n            : in  std_logic;
        serial_data_in   : in  std_logic;
        frame_sync_out   : out std_logic;
        frame_valid      : out std_logic;
        frame_data_out   : out std_logic_vector(7 downto 0);
        frame_data_valid : out std_logic
    );
end frame_sync;
architecture stub of frame_sync is
begin
    frame_sync_out <= '0';
    frame_valid <= '0';
    frame_data_out <= (others => '0');
    frame_data_valid <= '0';
end stub;



Run Simulation:
tclvsim -novopt work.fso_satcom_top_tb
add wave -r /*
run 50 ms

Verify Outputs:

Check LEDR and HEX0–HEX5 for each display_mode.
Verify rx_data_out matches input data (e.g., x"12345678" for valid frame).
Confirm rx_error_corrected is displayed when display_mode = "100".
Monitor GPIO for optical_tx_data, laser_enable, laser_power_ctrl, azimuth_angle, and elevation_angle.




Limitations

Missing Components: The testbench assumes stubs for undefined components. If actual implementations are available, replace stubs to test full functionality.
Simplified Serial Data: The send_serial_data procedure sends 40-bit frames at a 1 MHz rate. Adjust timing or data patterns based on frame_sync and deserializer requirements.
Error Correction: Assumes error_correction_codec detects/corrects errors in x"12345678FF". Provide its implementation for accurate testing.
PLL: Assumes pll_clocks provides clk_25mhz and clk_1mhz. If using an Intel PLL IP, ensure it’s included in the simulation.


Next Steps

Compile and Simulate:

Compile all necessary files in ModelSim.
Run the simulation and check waveforms for rx_data_valid, rx_error_corrected, link_quality, bit_error_rate, LEDR, and HEX0–HEX5.


Provide Missing Components:

If components like frame_sync, link_monitor, or system_control_fsm are available, share their VHDL to enhance the testbench.


Refine Stimuli:

Adjust send_serial_data timing or data patterns based on frame_sync or error_correction_codec specifics.
Add more test cases (e.g., multiple corrupted frames, varying laser power).


Debug Failures:

If outputs don’t match expectations (e.g., rx_data_out incorrect), check deserializer and error_correction_codec behavior.