--------------------------------------------------------------------------------
-- ADC_SAMPLING_CONTROLLER_HW_IP.vhd
--
-- Avalon-MM register wrapper around adc_trigger_engine, styled after the
-- existing TIMER_HW_IP.vhd register interface so it drops into a Platform
-- Designer / Qsys system the same way the timer IP does (cs_n / addr /
-- write_n / read_n / din / dout, 32-bit data, byte-addressable offsets
-- folded into a 4-bit word address exactly like TIMER_HW_IP).
--
-- ----------------------------------------------------------------------
-- Register map (word offsets, 32-bit registers unless noted)
-- ----------------------------------------------------------------------
--  0x0  CONTROL        (R/W)
--         [0]    RUN_ENABLE      : 1 = arm / continue sampling
--         [1]    SINGLE_SHOT     : 1 = stop automatically after one full
--                                  buffer fill, 0 = circular continuous capture
--         [2]    SOFT_RESET      : write 1 to reset the engine and timer
--         [7:3]  reserved
--  0x1  PRESCALER_SEL   (R/W)  -- bits [2:0] forwarded to the timer prescaler
--                                 (000 = div1/50MHz tick = max rate burst mode)
--  0x2  ADC_CHANNEL_SEL (R/W)  -- bits [4:0], MAX10 Modular ADC channel number
--  0x3  SAMPLE_PERIOD   (R/W)  -- ticks between trigger requests
--  0x4  STATUS          (R/O)
--         [0]    BUSY
--         [1]    OVERFLOW (circular mode wrapped since last clear)
--         [2]    SINGLE_SHOT_DONE (alias of NOT busy when single_shot=1)
--  0x5  SAMPLE_COUNT    (R/O)  -- current write pointer in the sample buffer
--  0x6  TRIGGER_LATENCY (R/O)  -- ticks between trigger and ADC response,
--                                 for jitter / pipeline-latency measurement
--  0x7  READ_ADDR       (R/W)  -- address to read back from the sample buffer
--  0x8  READ_DATA       (R/O)  -- buffer(READ_ADDR), one cycle after the
--                                 READ_ADDR write (matches sample_buffer's
--                                 one-cycle registered read port)
--
-- This mirrors TIMER_HW_IP's convention of a flat 4-bit word address
-- (16 possible offsets), cs_n-qualified synchronous writes, and
-- combinational (cs_n/read_n qualified) reads.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity ADC_SAMPLING_CONTROLLER_HW_IP is
   generic (
      ADC_DATA_WIDTH : integer := 12;
      ADC_CHAN_WIDTH : integer := 5;
      BUFFER_DEPTH   : integer := 1024;
      BUFFER_ADDR_W  : integer := 10
   );
   port (
      clk     : in  std_logic;
      reset_n : in  std_logic;

      -- Avalon-MM-style register interface (same shape as TIMER_HW_IP)
      cs_n    : in  std_logic;
      addr    : in  std_logic_vector(3 downto 0);
      write_n : in  std_logic;
      read_n  : in  std_logic;
      din     : in  std_logic_vector(31 downto 0);
      dout    : out std_logic_vector(31 downto 0);

      -- Status interrupt: pulses high for one cycle on completion of a
      -- single-shot run, suitable for wiring to a Nios V IRQ input.
      capture_done_int : out std_logic;

      -- Scope-visible sample-clock heartbeat (drive to a GPIO pin)
      adc_sample_clk_marker : out std_logic;

      -- ---------------- Avalon-ST command interface to Modular ADC -----
      adc_command_valid          : out std_logic;
      adc_command_channel        : out std_logic_vector(ADC_CHAN_WIDTH-1 downto 0);
      adc_command_startofpacket  : out std_logic;
      adc_command_endofpacket    : out std_logic;
      adc_command_ready          : in  std_logic;

      -- ---------------- Avalon-ST response interface from Modular ADC --
      adc_response_valid         : in  std_logic;
      adc_response_channel       : in  std_logic_vector(ADC_CHAN_WIDTH-1 downto 0);
      adc_response_data          : in  std_logic_vector(ADC_DATA_WIDTH-1 downto 0);
      adc_response_startofpacket : in  std_logic;
      adc_response_endofpacket   : in  std_logic
   );
end entity ADC_SAMPLING_CONTROLLER_HW_IP;

architecture rtl of ADC_SAMPLING_CONTROLLER_HW_IP is

   component adc_trigger_engine is
      generic (
         ADC_DATA_WIDTH : integer := 12;
         ADC_CHAN_WIDTH : integer := 5;
         BUFFER_DEPTH   : integer := 1024;
         BUFFER_ADDR_W  : integer := 10
      );
      port (
         clk             : in  std_logic;
         reset_n         : in  std_logic;
         run_enable      : in  std_logic;
         single_shot     : in  std_logic;
         trigger_enable  : in  std_logic;
         trigger_edge_falling : in std_logic;
         trigger_level   : in  std_logic_vector(ADC_DATA_WIDTH-1 downto 0);
         trigger_channel : in  std_logic_vector(ADC_CHAN_WIDTH-1 downto 0);
         pre_trigger_count  : in std_logic_vector(BUFFER_ADDR_W-1 downto 0);
         post_trigger_count : in std_logic_vector(BUFFER_ADDR_W-1 downto 0);
         scan_enable     : in  std_logic;
         scan_len        : in  std_logic_vector(2 downto 0);
         scan_table      : in  std_logic_vector(29 downto 0);
         adc_channel_sel : in  std_logic_vector(ADC_CHAN_WIDTH-1 downto 0);
         sample_period   : in  std_logic_vector(31 downto 0);
         prescaler_sel   : in  std_logic_vector(2 downto 0);
         busy            : out std_logic;
         sample_count    : out std_logic_vector(BUFFER_ADDR_W-1 downto 0);
         overflow_flag   : out std_logic;
         done_out        : out std_logic;
         triggered_out   : out std_logic;
         trigger_index_out : out std_logic_vector(BUFFER_ADDR_W-1 downto 0);
         adc_sample_clk_marker : out std_logic;
         adc_command_valid          : out std_logic;
         adc_command_channel        : out std_logic_vector(ADC_CHAN_WIDTH-1 downto 0);
         adc_command_startofpacket  : out std_logic;
         adc_command_endofpacket    : out std_logic;
         adc_command_ready          : in  std_logic;
         adc_response_valid         : in  std_logic;
         adc_response_channel       : in  std_logic_vector(ADC_CHAN_WIDTH-1 downto 0);
         adc_response_data          : in  std_logic_vector(ADC_DATA_WIDTH-1 downto 0);
         adc_response_startofpacket : in  std_logic;
         adc_response_endofpacket   : in  std_logic;
         rd_addr         : in  std_logic_vector(BUFFER_ADDR_W-1 downto 0);
         rd_data         : out std_logic_vector(15 downto 0)
      );
   end component;

   ------------------------------------------------------------------
   -- Register storage
   ------------------------------------------------------------------
   signal run_enable_reg      : std_logic := '0';
   signal single_shot_reg     : std_logic := '0';
   signal soft_reset_reg      : std_logic := '0';
   signal prescaler_sel_reg   : std_logic_vector(2 downto 0) := (others => '0');
   signal adc_channel_reg     : std_logic_vector(ADC_CHAN_WIDTH-1 downto 0) := (others => '0');
   signal sample_period_reg   : std_logic_vector(31 downto 0) := (others => '0');
   signal read_addr_reg       : std_logic_vector(BUFFER_ADDR_W-1 downto 0) := (others => '0');
   signal trigger_enable_reg  : std_logic := '0';
   signal trigger_edge_falling_reg : std_logic := '0';
   signal trigger_level_reg   : std_logic_vector(ADC_DATA_WIDTH-1 downto 0) := (others => '0');
   signal trigger_channel_reg : std_logic_vector(ADC_CHAN_WIDTH-1 downto 0) := (others => '0');
   signal pre_trigger_count_reg  : std_logic_vector(BUFFER_ADDR_W-1 downto 0) := (others => '0');
   signal post_trigger_count_reg : std_logic_vector(BUFFER_ADDR_W-1 downto 0) := (others => '0');
   signal scan_enable_reg     : std_logic := '0';
   signal scan_len_reg        : std_logic_vector(2 downto 0) := (others => '0');
   signal scan_table_reg      : std_logic_vector(29 downto 0) := (others => '0');

   ------------------------------------------------------------------
   -- Status from the engine
   ------------------------------------------------------------------
   signal busy_sig            : std_logic;
   signal sample_count_sig    : std_logic_vector(BUFFER_ADDR_W-1 downto 0);
   signal overflow_sig        : std_logic;
   signal read_data_sig       : std_logic_vector(15 downto 0);
   signal done_sig            : std_logic;
   signal triggered_sig       : std_logic;
   signal trigger_index_sig   : std_logic_vector(BUFFER_ADDR_W-1 downto 0);

   -- Combined internal reset: external reset_n OR soft_reset_reg
   signal engine_reset_n      : std_logic;

   signal done_prev           : std_logic := '0';
   signal adc_command_valid_sig         : std_logic;
   signal adc_command_channel_sig       : std_logic_vector(ADC_CHAN_WIDTH-1 downto 0);
   signal adc_command_startofpacket_sig : std_logic;
   signal adc_command_endofpacket_sig   : std_logic;

begin

   engine_reset_n <= reset_n and not soft_reset_reg;
   ----------------------------------------------------------------
   -- Register Read Process (combinational, qualified by cs_n/read_n,
   -- same style as TIMER_HW_IP.vhd)
   ----------------------------------------------------------------
   Bus_register_read_process :
   process(cs_n, read_n, addr, run_enable_reg, single_shot_reg,
           prescaler_sel_reg, adc_channel_reg, sample_period_reg,
           busy_sig, overflow_sig, sample_count_sig, trigger_index_sig,
           read_addr_reg, read_data_sig, done_sig, triggered_sig,
           trigger_enable_reg, trigger_edge_falling_reg, trigger_level_reg,
           trigger_channel_reg, pre_trigger_count_reg, post_trigger_count_reg,
           scan_enable_reg, scan_len_reg, scan_table_reg)
   begin
      if (cs_n = '0' and read_n = '0') then
         case addr is
            when "0000" =>
               dout <= (31 downto 3 => '0') &
                       "0" &                       -- bit2 reads back 0 (soft_reset is self-clearing)
                       single_shot_reg &
                       run_enable_reg;
            when "0001" =>
               dout <= (31 downto 3 => '0') & prescaler_sel_reg;
            when "0010" =>
               dout <= (31 downto ADC_CHAN_WIDTH => '0') & adc_channel_reg;
            when "0011" =>
               dout <= sample_period_reg;
            when "0100" =>
               dout <= (31 downto 4 => '0') &
                       triggered_sig &
                       done_sig &
                       overflow_sig &
                       busy_sig;
            when "0101" =>
               dout <= (31 downto BUFFER_ADDR_W => '0') & sample_count_sig;
            when "0110" =>
               dout <= (31 downto BUFFER_ADDR_W => '0') & trigger_index_sig;
            when "0111" =>
               dout <= (31 downto BUFFER_ADDR_W => '0') & read_addr_reg;
            when "1000" =>
               dout <= (31 downto 16 => '0') & read_data_sig;
            when "1001" =>
               dout <= (31 downto 2 => '0') &
                       trigger_edge_falling_reg &
                       trigger_enable_reg;
            when "1010" =>
               dout <= (31 downto ADC_DATA_WIDTH => '0') & trigger_level_reg;
            when "1011" =>
               dout <= (31 downto ADC_CHAN_WIDTH => '0') & trigger_channel_reg;
            when "1100" =>
               dout <= (31 downto BUFFER_ADDR_W => '0') & pre_trigger_count_reg;
            when "1101" =>
               dout <= (31 downto BUFFER_ADDR_W => '0') & post_trigger_count_reg;
            when "1110" =>
               dout <= (31 downto 4 => '0') &
                       scan_enable_reg &
                       scan_len_reg;
            when "1111" =>
               dout <= (31 downto 30 => '0') & scan_table_reg;
            when others =>
               dout <= (others => '0');
         end case;
      else
         dout <= (others => '0');
      end if;
   end process Bus_register_read_process;

   ----------------------------------------------------------------
   -- Register Write Process
   ----------------------------------------------------------------
   Bus_register_write_process :
   process(clk, reset_n)
   begin
      if reset_n = '0' then
         run_enable_reg    <= '0';
         single_shot_reg   <= '0';
         soft_reset_reg    <= '0';
         prescaler_sel_reg <= (others => '0');
         adc_channel_reg   <= (others => '0');
         sample_period_reg <= (others => '0');
         read_addr_reg     <= (others => '0');
         trigger_enable_reg <= '0';
         trigger_edge_falling_reg <= '0';
         trigger_level_reg  <= (others => '0');
         trigger_channel_reg <= (others => '0');
         pre_trigger_count_reg <= (others => '0');
         post_trigger_count_reg <= (others => '0');
         scan_enable_reg    <= '0';
         scan_len_reg       <= (others => '0');
         scan_table_reg     <= (others => '0');

      elsif rising_edge(clk) then
         -- soft_reset is a self-clearing one-cycle pulse into engine_reset_n
         soft_reset_reg <= '0';

         if (cs_n = '0' and write_n = '0') then
            case addr is
               when "0000" =>
                  run_enable_reg  <= din(0);
                  single_shot_reg <= din(1);
                  soft_reset_reg  <= din(2);
               when "0001" =>
                  prescaler_sel_reg <= din(2 downto 0);
               when "0010" =>
                  adc_channel_reg <= din(ADC_CHAN_WIDTH-1 downto 0);
               when "0011" =>
                  sample_period_reg <= din;
               when "0111" =>
                  read_addr_reg <= din(BUFFER_ADDR_W-1 downto 0);
               when "1001" =>
                  trigger_enable_reg <= din(0);
                  trigger_edge_falling_reg <= din(1);
               when "1010" =>
                  trigger_level_reg <= din(ADC_DATA_WIDTH-1 downto 0);
               when "1011" =>
                  trigger_channel_reg <= din(ADC_CHAN_WIDTH-1 downto 0);
               when "1100" =>
                  pre_trigger_count_reg <= din(BUFFER_ADDR_W-1 downto 0);
               when "1101" =>
                  post_trigger_count_reg <= din(BUFFER_ADDR_W-1 downto 0);
               when "1110" =>
                  scan_len_reg <= din(2 downto 0);
                  scan_enable_reg <= din(3);
               when "1111" =>
                  scan_table_reg <= din(29 downto 0);
               when others =>
                  null;
            end case;
         end if;
      end if;
   end process Bus_register_write_process;

   ----------------------------------------------------------------
   -- Capture-done interrupt: rising edge of (single_shot AND NOT busy),
   -- i.e. the run just completed because the buffer filled exactly once.
   ----------------------------------------------------------------
   irq_proc : process(clk, reset_n)
   begin
      if reset_n = '0' then
         done_prev <= '0';
         capture_done_int <= '0';
      elsif rising_edge(clk) then
         done_prev <= done_sig;
         if done_prev = '0' and done_sig = '1' then
            capture_done_int <= '1';
         else
            capture_done_int <= '0';
         end if;
      end if;
   end process irq_proc;

   ----------------------------------------------------------------
   -- ADC trigger engine instantiation
   ----------------------------------------------------------------
   u_engine : adc_trigger_engine
   generic map (
      ADC_DATA_WIDTH => ADC_DATA_WIDTH,
      ADC_CHAN_WIDTH => ADC_CHAN_WIDTH,
      BUFFER_DEPTH   => BUFFER_DEPTH,
      BUFFER_ADDR_W  => BUFFER_ADDR_W
   )
   port map (
      clk             => clk,
      reset_n         => engine_reset_n,
      run_enable      => run_enable_reg,
      single_shot     => single_shot_reg,
      trigger_enable  => trigger_enable_reg,
      trigger_edge_falling => trigger_edge_falling_reg,
      trigger_level   => trigger_level_reg,
      trigger_channel => trigger_channel_reg,
      pre_trigger_count => pre_trigger_count_reg,
      post_trigger_count => post_trigger_count_reg,
      scan_enable     => scan_enable_reg,
      scan_len        => scan_len_reg,
      scan_table      => scan_table_reg,
      adc_channel_sel => adc_channel_reg,
      sample_period   => sample_period_reg,
      prescaler_sel   => prescaler_sel_reg,
      busy            => busy_sig,
      sample_count    => sample_count_sig,
      overflow_flag   => overflow_sig,
      done_out        => done_sig,
      triggered_out   => triggered_sig,
      trigger_index_out => trigger_index_sig,
      adc_sample_clk_marker => adc_sample_clk_marker,

      adc_command_valid          => adc_command_valid_sig,
      adc_command_channel        => adc_command_channel_sig,
      adc_command_startofpacket  => adc_command_startofpacket_sig,
      adc_command_endofpacket    => adc_command_endofpacket_sig,
      adc_command_ready          => adc_command_ready,

      adc_response_valid         => adc_response_valid,
      adc_response_channel       => adc_response_channel,
      adc_response_data          => adc_response_data,
      adc_response_startofpacket => adc_response_startofpacket,
      adc_response_endofpacket   => adc_response_endofpacket,

      rd_addr => read_addr_reg,
      rd_data => read_data_sig
   );

   adc_command_valid         <= adc_command_valid_sig;
   adc_command_channel       <= adc_command_channel_sig;
   adc_command_startofpacket <= adc_command_startofpacket_sig;
   adc_command_endofpacket   <= adc_command_endofpacket_sig;

end architecture rtl;
