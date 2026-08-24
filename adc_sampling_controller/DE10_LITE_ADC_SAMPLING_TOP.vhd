--------------------------------------------------------------------------------
-- DE10_LITE_ADC_SAMPLING_TOP.vhd
--
-- Board-level wrapper for the Platform Designer system `adc_c`.
-- The generated Qsys subsystem already contains:
--   - ADC_SAMPLING_CONTROLLER_HW_IP
--   - Modular ADC
--   - Nios V/m
--   - PLL
--   - JTAG UART
--   - On-chip RAM
--
-- This top-level intentionally instantiates only:
--   - adc_c
--   - seg7_decoder
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity DE10_LITE_ADC_SAMPLING_TOP is
   port (
      -- Clocks
      MAX10_CLK1_50 : in  std_logic;

      -- User I/O
      KEY  : in  std_logic_vector(1 downto 0);  -- active-low push-buttons
      SW   : in  std_logic_vector(9 downto 0);  -- slide switches
      LEDR : out std_logic_vector(9 downto 0);
      HEX0 : out std_logic_vector(7 downto 0);
      HEX1 : out std_logic_vector(7 downto 0);
      HEX2 : out std_logic_vector(7 downto 0);
      HEX3 : out std_logic_vector(7 downto 0);
      HEX4 : out std_logic_vector(7 downto 0);
      HEX5 : out std_logic_vector(7 downto 0);

      -- Arduino header analog inputs feed the MAX10 internal ADC1 directly
      -- in hardware; no FPGA pin mapping is needed/possible for the analog
      -- side (see docs/IP_GENERATION_NOTES.md). One digital GPIO pin is
      -- used here purely to expose the sample-clock heartbeat for probing.
      ARDUINO_IO : out std_logic_vector(15 downto 0)
   );
end entity DE10_LITE_ADC_SAMPLING_TOP;

architecture rtl of DE10_LITE_ADC_SAMPLING_TOP is

   component adc_c is
      port (
         adc_sampling_controller_hw_ip_0_sample_marker_conduit : out std_logic;
         clk_clk                                               : in  std_logic;
         hex0_export                                           : out std_logic_vector(7 downto 0);
         hex1_export                                           : out std_logic_vector(7 downto 0);
         hex2_export                                           : out std_logic_vector(7 downto 0);
         hex3_export                                           : out std_logic_vector(7 downto 0);
         hex4_export                                           : out std_logic_vector(7 downto 0);
         hex5_export                                           : out std_logic_vector(7 downto 0);
         reset_reset_n                                         : in  std_logic
      );
   end component;

   signal sample_clk_marker       : std_logic;
   signal sample_clk_marker_d     : std_logic := '0';
   signal sample_marker_toggle    : std_logic := '0';
   signal probe_divider           : unsigned(11 downto 0) := (others => '0');

begin

   u_adc_c : adc_c
   port map (
      adc_sampling_controller_hw_ip_0_sample_marker_conduit => sample_clk_marker,
      clk_clk                                               => MAX10_CLK1_50,
      hex0_export                                           => HEX0,
      hex1_export                                           => HEX1,
      hex2_export                                           => HEX2,
      hex3_export                                           => HEX3,
      hex4_export                                           => HEX4,
      hex5_export                                           => HEX5,
      reset_reset_n                                         => KEY(1)
   );

   process (MAX10_CLK1_50)
   begin
      if rising_edge(MAX10_CLK1_50) then
         if KEY(1) = '0' then
            sample_clk_marker_d  <= '0';
            sample_marker_toggle <= '0';
            probe_divider        <= (others => '0');
         else
            sample_clk_marker_d <= sample_clk_marker;
            probe_divider       <= probe_divider + 1;

            if sample_clk_marker = '1' and sample_clk_marker_d = '0' then
               sample_marker_toggle <= not sample_marker_toggle;
            end if;
         end if;
      end if;
   end process;

   LEDR(0) <= sample_clk_marker;
   LEDR(1) <= not KEY(1);
   LEDR(9 downto 2) <= SW(7 downto 0);

   ARDUINO_IO(0) <= std_logic(probe_divider(probe_divider'high));
   ARDUINO_IO(1) <= sample_clk_marker;
   ARDUINO_IO(2) <= sample_marker_toggle;
   ARDUINO_IO(3) <= KEY(1);
   ARDUINO_IO(15 downto 4) <= (others => '0');
end architecture rtl;
