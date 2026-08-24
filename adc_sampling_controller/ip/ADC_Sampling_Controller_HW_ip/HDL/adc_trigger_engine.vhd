--------------------------------------------------------------------------------
-- adc_trigger_engine.vhd
--
-- Core of the High-Speed ADC Sampling Controller.
--
-- This block wires the existing TIMER_HW_IP (compare-match channel of the
-- shared timer/PWM/capture IP) directly to the Altera Modular ADC IP's
-- Avalon-ST-style command interface, to generate a precise, jitter-free,
-- periodic ADC start-of-conversion pulse, and captures the returned samples
-- into a dual-port buffer for later read-back.
--
-- ----------------------------------------------------------------------
-- How the timer is used
-- ----------------------------------------------------------------------
-- The timer free-running counter is configured (via its own register map,
-- exactly as in TIMER_HW_IP) in countup / auto mode:
--    - load_value    = 0
--    - compare_value = SAMPLE_PERIOD - 1   (in prescaled clock ticks)
--    - prescaler     = 000 (div 1) for max-rate burst capture at 50 MHz
--
-- Every time the counter reaches compare_value, timer_comparator emits a
-- single clock-wide compare_int pulse (rising edge of match, see
-- timer_comparator.vhd). This engine uses that pulse to:
--   1. Issue one ADC command_valid pulse (start-of-packet + end-of-packet,
--      single-beat transfer) requesting a conversion on ADC_CHANNEL.
--   2. Re-arm the timer counter back to 0 on the same cycle by pulsing the
--      timer's own "reset" control encoding through Control_timer, so the
--      counter restarts immediately and the next compare event is exactly
--      SAMPLE_PERIOD ticks later -- giving a constant, hardware-timed
--      sample period with no software jitter.
--
-- The ADC response (response_valid / response_data) is asynchronous to the
-- trigger pulse by some fixed pipeline latency inside the Modular ADC IP;
-- this engine simply watches response_valid and writes every arriving
-- sample into the sample_buffer at the next free address, wrapping at
-- BUFFER_DEPTH (circular capture) until a run is stopped or the buffer is
-- read out.
--
-- ----------------------------------------------------------------------
-- Why not just use the timer's PWM or capture path instead of compare_int?
-- ----------------------------------------------------------------------
-- compare_int is already a clean, registered, single-cycle pulse generated
-- by timer_comparator (match_now and not prev_match), so it is the ideal
-- trigger source: no pulse stretching, no combinational glitches. The PWM
-- output is kept available on adc_sample_clk_marker purely as a
-- scope-visible heartbeat for lab debugging (same compare_value, so its
-- falling edge lines up with every trigger). The capture unit is reused to
-- timestamp the trigger-to-response latency for jitter measurement,
-- exposed through the status register.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity adc_trigger_engine is
   generic (
      ADC_DATA_WIDTH  : integer := 12;
      ADC_CHAN_WIDTH  : integer := 5;
      BUFFER_DEPTH    : integer := 1024;
      BUFFER_ADDR_W   : integer := 10
   );
   port (
      clk             : in  std_logic;
      reset_n         : in  std_logic;

      -- ---------------- Control / configuration ----------------------
      run_enable      : in  std_logic;                      -- 1 = arm and run continuously
      single_shot     : in  std_logic;                      -- 1 = capture exactly BUFFER_DEPTH samples then stop
      trigger_enable  : in  std_logic;                      -- 1 = pre-trigger circular capture, then stop after trigger+post
      trigger_edge_falling : in std_logic;                  -- 0=rising, 1=falling
      trigger_level   : in  std_logic_vector(ADC_DATA_WIDTH-1 downto 0);
      trigger_channel : in  std_logic_vector(ADC_CHAN_WIDTH-1 downto 0);
      pre_trigger_count  : in std_logic_vector(BUFFER_ADDR_W-1 downto 0);
      post_trigger_count : in std_logic_vector(BUFFER_ADDR_W-1 downto 0);
      scan_enable     : in  std_logic;
      scan_len        : in  std_logic_vector(2 downto 0);   -- 1..6
      scan_table      : in  std_logic_vector(29 downto 0);  -- 6 x 5-bit packed channels
      adc_channel_sel : in  std_logic_vector(ADC_CHAN_WIDTH-1 downto 0);
      sample_period   : in  std_logic_vector(31 downto 0);  -- ticks between triggers
      prescaler_sel   : in  std_logic_vector(2 downto 0);   -- forwarded to timer prescaler

      -- ---------------- Status -----------------------------------------
      busy            : out std_logic;                      -- run in progress
      sample_count    : out std_logic_vector(BUFFER_ADDR_W-1 downto 0);
      overflow_flag   : out std_logic;                       -- buffer wrapped (circular mode)
      done_out        : out std_logic;
      triggered_out   : out std_logic;
      trigger_index_out : out std_logic_vector(BUFFER_ADDR_W-1 downto 0);
      trigger_latency : out std_logic_vector(31 downto 0);   -- captured trigger->response latency (timer ticks)
      adc_sample_clk_marker : out std_logic;                 -- scope-visible heartbeat (timer PWM)

      -- ---------------- Avalon-ST command interface to Modular ADC -----
      adc_command_valid        : out std_logic;
      adc_command_channel      : out std_logic_vector(ADC_CHAN_WIDTH-1 downto 0);
      adc_command_startofpacket: out std_logic;
      adc_command_endofpacket  : out std_logic;
      adc_command_ready        : in  std_logic;

      -- ---------------- Avalon-ST response interface from Modular ADC --
      adc_response_valid       : in  std_logic;
      adc_response_channel     : in  std_logic_vector(ADC_CHAN_WIDTH-1 downto 0);
      adc_response_data        : in  std_logic_vector(ADC_DATA_WIDTH-1 downto 0);
      adc_response_startofpacket : in std_logic;
      adc_response_endofpacket   : in std_logic;

      -- ---------------- Read-back port into the sample buffer ----------
      rd_addr         : in  std_logic_vector(BUFFER_ADDR_W-1 downto 0);
      rd_data         : out std_logic_vector(15 downto 0)
   );
end entity adc_trigger_engine;

architecture rtl of adc_trigger_engine is

   ------------------------------------------------------------------
   -- Timer IP component (reused as-is, unmodified)
   ------------------------------------------------------------------
   component timer is
      generic (
         TIMER_WIDTH : integer := 32
      );
      port (
         clk            : in  std_logic;
         reset_n        : in  std_logic;
         Control_timer  : in  std_logic_vector(7 downto 0);
         timer_data     : out std_logic_vector(31 downto 0);
         load_value     : in  std_logic_vector(31 downto 0);
         compare_value  : in  std_logic_vector(31 downto 0);
         status_reg     : out std_logic_vector(7 downto 0);
         capture_data   : out std_logic_vector(31 downto 0);
         ext_capture    : in  std_logic;
         compare_int    : out std_logic;
         overflow_int   : out std_logic;
         pwm_out        : out std_logic
      );
   end component;

   component sample_buffer is
      generic (
         DATA_WIDTH : integer := 12;
         DEPTH      : integer := 1024;
         ADDR_WIDTH : integer := 10
      );
      port (
         clk     : in  std_logic;
         wr_en   : in  std_logic;
         wr_addr : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
         wr_data : in  std_logic_vector(DATA_WIDTH-1 downto 0);
         rd_addr : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
         rd_data : out std_logic_vector(DATA_WIDTH-1 downto 0)
      );
   end component;

   ------------------------------------------------------------------
   -- Timer-facing signals
   ------------------------------------------------------------------
   signal control_timer_sig : std_logic_vector(7 downto 0);
   signal compare_int_sig   : std_logic;
   signal pwm_out_sig       : std_logic;
   signal capture_data_sig  : std_logic_vector(31 downto 0);
   signal timer_compare_sig : std_logic_vector(31 downto 0);

   -- Re-arm pulse: one cycle after compare_int we drive the timer's
   -- "reset" control code ("01") so the counter restarts at 0. The
   -- following cycle we go back to "start" ("10") so it free-runs again.
   type rearm_state_t is (RUN, REARM);
   signal rearm_state : rearm_state_t := RUN;

   ------------------------------------------------------------------
   -- ADC command / response handling
   ------------------------------------------------------------------
   signal cmd_valid_sig   : std_logic := '0';

   signal wr_addr_reg     : unsigned(BUFFER_ADDR_W-1 downto 0) := (others => '0');
   signal wr_addr_write_reg : std_logic_vector(BUFFER_ADDR_W-1 downto 0) := (others => '0');
   signal wr_en_sig       : std_logic := '0';
   signal overflow_reg    : std_logic := '0';

   signal busy_reg        : std_logic := '0';
   signal done_reg        : std_logic := '0';
   signal triggered_reg   : std_logic := '0';
   signal trigger_index_reg : unsigned(BUFFER_ADDR_W-1 downto 0) := (others => '0');
   signal post_remaining  : unsigned(BUFFER_ADDR_W-1 downto 0) := (others => '0');

   signal last_sample_valid : std_logic := '0';
   signal last_sample       : unsigned(ADC_DATA_WIDTH-1 downto 0) := (others => '0');

   signal scan_idx        : unsigned(2 downto 0) := (others => '0');
   signal scan_len_u      : unsigned(2 downto 0);
   signal cmd_channel_sig : std_logic_vector(ADC_CHAN_WIDTH-1 downto 0);

   signal sample_word_reg : std_logic_vector(15 downto 0) := (others => '0');
   signal samples_seen    : unsigned(BUFFER_ADDR_W downto 0) := (others => '0');

   function scan_chan_at(idx : unsigned(2 downto 0); table : std_logic_vector(29 downto 0)) return std_logic_vector is
      variable i : integer;
      variable base : integer;
      variable out_ch : std_logic_vector(ADC_CHAN_WIDTH-1 downto 0);
   begin
      i := to_integer(idx);
      if i < 0 then
         i := 0;
      elsif i > 5 then
         i := 5;
      end if;
      base := i * 5;
      out_ch := table(base + 4 downto base);
      return out_ch;
   end function;

   ------------------------------------------------------------------
   -- Jitter / latency measurement via the timer's capture unit:
   -- ext_capture is pulsed by the arriving ADC response, capturing the
   -- timer's free-running value at that instant. Subtracting the value
   -- latched at the trigger (which is always 0 right after re-arm, since
   -- the counter is reset to 0 on every trigger) directly gives the
   -- trigger-to-response latency in timer ticks.
   ------------------------------------------------------------------
   signal ext_capture_sig  : std_logic := '0';

begin

   scan_len_u <= unsigned(scan_len);

   cmd_channel_sig <= scan_chan_at(scan_idx, scan_table) when scan_enable = '1' else adc_channel_sel;

   -- The public register is a period in ticks. The reused timer comparator
   -- fires when timer_value equals compare_value, starting from zero.
   timer_compare_sig <= std_logic_vector(unsigned(sample_period) - 1)
      when sample_period /= x"00000000" else
      (others => '0');

   ------------------------------------------------------------------
   -- Control register encoding for the timer (see timer.vhd header):
   --   [7:5] prescaler_sel
   --   [4]   PWM enable          -> always on, used as scope marker
   --   [3]   countdown mode      -> 0, we count up
   --   [2]   sw capture trigger  -> unused here, ext_capture used instead
   --   [1:0] "10"=start "01"=reset "00"=stop "11"=load
   ------------------------------------------------------------------
   control_timer_sig(7 downto 5) <= prescaler_sel;
   control_timer_sig(4)          <= '1';                 -- PWM enable (scope marker)
   control_timer_sig(3)          <= '0';                 -- count up
   control_timer_sig(2)          <= '0';                 -- no sw capture (ext_capture used)
   control_timer_sig(1 downto 0) <= "01" when (rearm_state = REARM) else
                                     "10" when (run_enable = '1' and done_reg = '0') else
                                     "00";

   ------------------------------------------------------------------
   -- Timer instantiation: the heart of the sample-rate generator.
   -- load_value is held at 0 because re-arm always brings the counter
   -- back to 0 via the reset control code, not via an explicit load.
   ------------------------------------------------------------------
   u_timer : timer
   generic map (TIMER_WIDTH => 32)
   port map (
      clk           => clk,
      reset_n       => reset_n,
      Control_timer => control_timer_sig,
      timer_data    => open,
      load_value    => (others => '0'),
      compare_value => timer_compare_sig,
      status_reg    => open,
      capture_data  => capture_data_sig,
      ext_capture   => ext_capture_sig,
      compare_int   => compare_int_sig,
      overflow_int  => open,
      pwm_out       => pwm_out_sig
   );

   adc_sample_clk_marker <= pwm_out_sig;
   trigger_latency        <= capture_data_sig;

   ------------------------------------------------------------------
   -- Re-arm sequencer: returns the counter to 0 exactly one cycle after
   -- every compare match, so the period between triggers is always
   -- exactly (sample_period + 1) ticks of the prescaled clock, with no
   -- accumulated drift.
   ------------------------------------------------------------------
   rearm_proc : process(clk, reset_n)
   begin
      if reset_n = '0' then
         rearm_state <= RUN;
      elsif rising_edge(clk) then
         case rearm_state is
            when RUN =>
               if compare_int_sig = '1' then
                  rearm_state <= REARM;
               end if;
            when REARM =>
               rearm_state <= RUN;
         end case;
      end if;
   end process rearm_proc;

   ------------------------------------------------------------------
   -- Trigger -> ADC command generation.
   -- On every compare_int pulse, issue a single-beat Avalon-ST command
   -- (start-of-packet and end-of-packet both asserted) requesting a
   -- conversion on adc_channel_sel. cmd_valid_sig is held until the ADC
   -- core asserts command_ready, matching the standard ready/valid
   -- handshake of the Modular ADC IP's command stream.
   ------------------------------------------------------------------
   cmd_proc : process(clk, reset_n)
   begin
      if reset_n = '0' then
         cmd_valid_sig <= '0';
         scan_idx      <= (others => '0');
      elsif rising_edge(clk) then
         if compare_int_sig = '1' and run_enable = '1' and done_reg = '0' then
            cmd_valid_sig <= '1';
         elsif cmd_valid_sig = '1' and adc_command_ready = '1' then
            cmd_valid_sig <= '0';
            if scan_enable = '1' then
               if scan_len_u <= 1 then
                  scan_idx <= (others => '0');
               elsif scan_idx = (scan_len_u - 1) then
                  scan_idx <= (others => '0');
               else
                  scan_idx <= scan_idx + 1;
               end if;
            else
               scan_idx <= (others => '0');
            end if;
         end if;
      end if;
   end process cmd_proc;

   adc_command_valid         <= cmd_valid_sig;
   adc_command_channel       <= cmd_channel_sig;
   adc_command_startofpacket <= cmd_valid_sig;
   adc_command_endofpacket   <= cmd_valid_sig;

   ------------------------------------------------------------------
   -- Response capture: every arriving ADC sample is written into the
   -- circular sample buffer, and simultaneously used to fire the
   -- timer's external-capture input so the trigger-to-response latency
   -- can be read back through trigger_latency for jitter analysis.
   ------------------------------------------------------------------
   ext_capture_sig <= adc_response_valid;

   capture_proc : process(clk, reset_n)
      variable level_u : unsigned(ADC_DATA_WIDTH-1 downto 0);
      variable sample_u : unsigned(ADC_DATA_WIDTH-1 downto 0);
      variable trigger_hit : std_logic;
      variable trig_chan_match : std_logic;
      variable enough_history : std_logic;
   begin
      if reset_n = '0' then
         wr_addr_reg      <= (others => '0');
         overflow_reg     <= '0';
         busy_reg         <= '0';
         done_reg         <= '0';
         triggered_reg    <= '0';
         trigger_index_reg <= (others => '0');
         post_remaining   <= (others => '0');
         last_sample_valid <= '0';
         last_sample       <= (others => '0');
         wr_en_sig        <= '0';
         samples_seen     <= (others => '0');
      elsif rising_edge(clk) then
         wr_en_sig <= '0';

         if run_enable = '0' then
            -- Idle: clear status, ready for a fresh run on next run_enable
            busy_reg         <= '0';
            done_reg         <= '0';
            overflow_reg     <= '0';
            wr_addr_reg      <= (others => '0');
            triggered_reg    <= '0';
            trigger_index_reg <= (others => '0');
            post_remaining   <= (others => '0');
            last_sample_valid <= '0';
            samples_seen     <= (others => '0');
         else
            if done_reg = '1' then
               busy_reg <= '0';
            else
               busy_reg <= '1';
            end if;

            if adc_response_valid = '1' and done_reg = '0' then
               wr_en_sig <= '1';
               wr_addr_write_reg <= std_logic_vector(wr_addr_reg);
               sample_word_reg <= adc_response_channel(3 downto 0) & adc_response_data;
               sample_u := unsigned(adc_response_data);
               last_sample <= sample_u;
               last_sample_valid <= '1';

               level_u := unsigned(trigger_level);
               trig_chan_match := '0';
               if adc_response_channel = trigger_channel then
                  trig_chan_match := '1';
               end if;

               trigger_hit := '0';
               enough_history := '0';
               if samples_seen >= unsigned('0' & pre_trigger_count) then
                  enough_history := '1';
               end if;

               if trigger_enable = '1' and triggered_reg = '0' and last_sample_valid = '1' and trig_chan_match = '1' and enough_history = '1' then
                  if trigger_edge_falling = '0' then
                     if last_sample < level_u and sample_u >= level_u then
                        trigger_hit := '1';
                     end if;
                  else
                     if last_sample > level_u and sample_u <= level_u then
                        trigger_hit := '1';
                     end if;
                  end if;
               end if;

               if trigger_hit = '1' then
                  triggered_reg <= '1';
                  trigger_index_reg <= wr_addr_reg;
                  post_remaining <= unsigned(post_trigger_count);
                  if unsigned(post_trigger_count) = 0 then
                     done_reg <= '1';
                  end if;
               elsif trigger_enable = '1' and triggered_reg = '1' then
                  if post_remaining /= 0 then
                     post_remaining <= post_remaining - 1;
                     if post_remaining = 1 then
                        done_reg <= '1';
                     end if;
                  end if;
               elsif trigger_enable = '0' and single_shot = '1' then
                  if wr_addr_reg = to_unsigned(BUFFER_DEPTH-1, BUFFER_ADDR_W) then
                     done_reg <= '1';
                  end if;
               end if;

               if wr_addr_reg = to_unsigned(BUFFER_DEPTH-1, BUFFER_ADDR_W) then
                  wr_addr_reg <= (others => '0');
                  if trigger_enable = '0' and single_shot = '0' then
                     overflow_reg <= '1';
                  end if;
               else
                  wr_addr_reg <= wr_addr_reg + 1;
               end if;

               if samples_seen < to_unsigned(BUFFER_DEPTH, samples_seen'length) then
                  samples_seen <= samples_seen + 1;
               end if;
            end if;
         end if;
      end if;
   end process capture_proc;

   busy          <= busy_reg;
   sample_count  <= std_logic_vector(wr_addr_reg);
   overflow_flag <= overflow_reg;
   done_out      <= done_reg;
   triggered_out <= triggered_reg;
   trigger_index_out <= std_logic_vector(trigger_index_reg);

   ------------------------------------------------------------------
   -- Sample buffer instantiation
   ------------------------------------------------------------------
   u_sample_buffer : sample_buffer
   generic map (
      DATA_WIDTH => 16,
      DEPTH      => BUFFER_DEPTH,
      ADDR_WIDTH => BUFFER_ADDR_W
   )
   port map (
      clk     => clk,
      wr_en   => wr_en_sig,
      wr_addr => wr_addr_write_reg,
      wr_data => sample_word_reg,
      rd_addr => rd_addr,
      rd_data => rd_data
   );

end architecture rtl;
