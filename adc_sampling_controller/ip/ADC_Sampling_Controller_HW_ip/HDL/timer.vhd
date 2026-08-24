LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

-- Timer Top-Level: Orchestrates all timer modules
-- Combines prescaler, counter, comparator, capture, and PWM
ENTITY timer IS
   GENERIC (
      TIMER_WIDTH : integer := 32
   );
   PORT (
      clk            : IN std_logic;
      reset_n        : IN std_logic;
      
      -- Control Register (8 bits)
      -- [7:5] = Prescaler select (0-7 for div 1,2,4,8,16,32,64,128)
      -- [4] = PWM enable
      -- [3] = Countdown mode
      -- [2] = Software capture trigger
      -- [1:0] = Start/Stop/Reset: "10"=start, "00"=stop, "01"=reset, "11"=load
      Control_timer  : IN std_logic_vector(7 downto 0);
      
      -- Data ports
      timer_data     : OUT std_logic_vector(TIMER_WIDTH-1 DOWNTO 0);
      load_value     : IN std_logic_vector(TIMER_WIDTH-1 DOWNTO 0);
      compare_value  : IN std_logic_vector(TIMER_WIDTH-1 DOWNTO 0);
      
      -- Status Register (8 bits)
      -- [0] = Running flag
      -- [1] = Overflow flag
      -- [2] = Compare match flag
      -- [3] = Capture valid flag
      -- [4] = PWM output
      status_reg     : OUT std_logic_vector(7 downto 0);
      
      -- Capture register
      capture_data   : OUT std_logic_vector(TIMER_WIDTH-1 DOWNTO 0);
      
      -- External signals
      ext_capture    : IN std_logic;
      compare_int    : OUT std_logic;
      overflow_int   : OUT std_logic;
      pwm_out        : OUT std_logic
   );
END timer;

ARCHITECTURE rtl OF timer IS

   -- Component declarations
   component timer_prescaler is
      PORT (
         clk           : IN std_logic;
         reset_n       : IN std_logic;
         prescaler_sel : IN std_logic_vector(2 downto 0);
         clock_enable  : OUT std_logic
      );
   end component;

   component timer_counter is
      GENERIC (TIMER_WIDTH : integer := 32);
      PORT (
         clk           : IN std_logic;
         reset_n       : IN std_logic;
         clock_enable  : IN std_logic;
         timer_start   : IN std_logic;
         timer_stop    : IN std_logic;
         timer_reset   : IN std_logic;
         timer_load    : IN std_logic;
         countdown_en  : IN std_logic;
         load_value    : IN std_logic_vector(TIMER_WIDTH-1 downto 0);
         timer_value   : OUT std_logic_vector(TIMER_WIDTH-1 downto 0);
         running       : OUT std_logic;
         overflow      : OUT std_logic
      );
   end component;

   component timer_comparator is
      GENERIC (TIMER_WIDTH : integer := 32);
      PORT (
         clk           : IN std_logic;
         reset_n       : IN std_logic;
         timer_value   : IN std_logic_vector(TIMER_WIDTH-1 downto 0);
         compare_value : IN std_logic_vector(TIMER_WIDTH-1 downto 0);
         compare_flag  : OUT std_logic;
         compare_int   : OUT std_logic
      );
   end component;

   component timer_capture is
      GENERIC (TIMER_WIDTH : integer := 32);
      PORT (
         clk           : IN std_logic;
         reset_n       : IN std_logic;
         timer_value   : IN std_logic_vector(TIMER_WIDTH-1 downto 0);
         ext_capture   : IN std_logic;
         sw_capture    : IN std_logic;
         capture_data  : OUT std_logic_vector(TIMER_WIDTH-1 downto 0);
         capture_valid : OUT std_logic
      );
   end component;

   component timer_pwm is
      GENERIC (TIMER_WIDTH : integer := 32);
      PORT (
         clk           : IN std_logic;
         reset_n       : IN std_logic;
         pwm_enable    : IN std_logic;
         timer_value   : IN std_logic_vector(TIMER_WIDTH-1 downto 0);
         compare_value : IN std_logic_vector(TIMER_WIDTH-1 downto 0);
         pwm_out       : OUT std_logic
      );
   end component;

   -- Internal signals
   SIGNAL clock_enable_sig    : std_logic;
   SIGNAL timer_value_sig     : std_logic_vector(TIMER_WIDTH-1 downto 0);
   SIGNAL running_sig         : std_logic;
   SIGNAL overflow_sig        : std_logic;
   SIGNAL compare_flag_sig    : std_logic;
   SIGNAL compare_int_sig     : std_logic;
   SIGNAL capture_data_sig    : std_logic_vector(TIMER_WIDTH-1 downto 0);
   SIGNAL capture_valid_sig   : std_logic;
   SIGNAL pwm_out_sig         : std_logic;
   
   -- Control signal decoding
   SIGNAL prescaler_sel       : std_logic_vector(2 downto 0);
   SIGNAL pwm_enable_sig      : std_logic;
   SIGNAL countdown_mode_sig  : std_logic;
   SIGNAL sw_capture_sig      : std_logic;
   SIGNAL timer_start_sig     : std_logic;
   SIGNAL timer_stop_sig      : std_logic;
   SIGNAL timer_reset_sig     : std_logic;
   SIGNAL timer_load_sig      : std_logic;

BEGIN

   -- Decode control signals
   prescaler_sel <= Control_timer(7 downto 5);
   pwm_enable_sig <= Control_timer(4);
   countdown_mode_sig <= Control_timer(3);
   sw_capture_sig <= Control_timer(2);
   timer_start_sig <= '1' when Control_timer(1 downto 0) = "10" else '0';
   timer_stop_sig <= '1' when Control_timer(1 downto 0) = "00" else '0';
   timer_reset_sig <= '1' when Control_timer(1 downto 0) = "01" else '0';
   timer_load_sig <= '1' when Control_timer(1 downto 0) = "11" else '0';

   ---------------------------------------------------------------
   -- Prescaler Instantiation
   ---------------------------------------------------------------
   u_prescaler : timer_prescaler
   PORT MAP (
      clk           => clk,
      reset_n       => reset_n,
      prescaler_sel => prescaler_sel,
      clock_enable  => clock_enable_sig
   );

   ---------------------------------------------------------------
   -- Counter Instantiation
   ---------------------------------------------------------------
   u_counter : timer_counter
   GENERIC MAP (TIMER_WIDTH => TIMER_WIDTH)
   PORT MAP (
      clk           => clk,
      reset_n       => reset_n,
      clock_enable  => clock_enable_sig,
      timer_start   => timer_start_sig,
      timer_stop    => timer_stop_sig,
      timer_reset   => timer_reset_sig,
      timer_load    => timer_load_sig,
      countdown_en  => countdown_mode_sig,
      load_value    => load_value,
      timer_value   => timer_value_sig,
      running       => running_sig,
      overflow      => overflow_sig
   );

   ---------------------------------------------------------------
   -- Comparator Instantiation
   ---------------------------------------------------------------
   u_comparator : timer_comparator
   GENERIC MAP (TIMER_WIDTH => TIMER_WIDTH)
   PORT MAP (
      clk           => clk,
      reset_n       => reset_n,
      timer_value   => timer_value_sig,
      compare_value => compare_value,
      compare_flag  => compare_flag_sig,
      compare_int   => compare_int_sig
   );

   ---------------------------------------------------------------
   -- Capture Instantiation
   ---------------------------------------------------------------
   u_capture : timer_capture
   GENERIC MAP (TIMER_WIDTH => TIMER_WIDTH)
   PORT MAP (
      clk           => clk,
      reset_n       => reset_n,
      timer_value   => timer_value_sig,
      ext_capture   => ext_capture,
      sw_capture    => sw_capture_sig,
      capture_data  => capture_data_sig,
      capture_valid => capture_valid_sig
   );

   ---------------------------------------------------------------
   -- PWM Instantiation
   ---------------------------------------------------------------
   u_pwm : timer_pwm
   GENERIC MAP (TIMER_WIDTH => TIMER_WIDTH)
   PORT MAP (
      clk           => clk,
      reset_n       => reset_n,
      pwm_enable    => pwm_enable_sig,
      timer_value   => timer_value_sig,
      compare_value => compare_value,
      pwm_out       => pwm_out_sig
   );

   ---------------------------------------------------------------
   -- Output Assignments
   ---------------------------------------------------------------
   timer_data <= timer_value_sig;
   capture_data <= capture_data_sig;
   compare_int <= compare_int_sig;
   overflow_int <= overflow_sig;
   pwm_out <= pwm_out_sig;
   
   -- Status register
   status_reg(0) <= running_sig;
   status_reg(1) <= overflow_sig;
   status_reg(2) <= compare_flag_sig;
   status_reg(3) <= capture_valid_sig;
   status_reg(4) <= pwm_out_sig;
   status_reg(7 downto 5) <= "000";

END rtl;
