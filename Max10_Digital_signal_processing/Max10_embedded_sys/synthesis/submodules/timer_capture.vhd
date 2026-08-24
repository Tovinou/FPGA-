LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

-- Timer Capture: Captures timer value on external trigger or software command
ENTITY timer_capture IS
   GENERIC (
      TIMER_WIDTH : integer := 32
   );
   PORT (
      clk           : IN std_logic;
      reset_n       : IN std_logic;
      
      timer_value   : IN std_logic_vector(TIMER_WIDTH-1 downto 0);
      ext_capture   : IN std_logic;              -- External capture trigger (rising edge)
      sw_capture    : IN std_logic;              -- Software capture trigger
      
      capture_data  : OUT std_logic_vector(TIMER_WIDTH-1 downto 0);
      capture_valid : OUT std_logic
   );
END timer_capture;

ARCHITECTURE rtl OF timer_capture IS
   SIGNAL capture_reg     : unsigned(TIMER_WIDTH-1 downto 0) := (others => '0');
   SIGNAL valid_flag      : std_logic := '0';
   SIGNAL prev_ext_cap    : std_logic := '0';
   
BEGIN

   -- Edge detection and capture logic
   Capture_process : PROCESS(clk, reset_n)
      VARIABLE ext_edge : std_logic;
   BEGIN
      if reset_n = '0' then
         capture_reg <= (others => '0');
         valid_flag <= '0';
         prev_ext_cap <= '0';
         
      elsif rising_edge(clk) then
         ext_edge := ext_capture and not prev_ext_cap;
         prev_ext_cap <= ext_capture;
         
         -- Capture on external trigger or software command
         if ext_edge = '1' or sw_capture = '1' then
            capture_reg <= unsigned(timer_value);
            valid_flag <= '1';
         end if;
      end if;
   END PROCESS Capture_process;

   -- Outputs
   capture_data <= std_logic_vector(capture_reg);
   capture_valid <= valid_flag;

END rtl;
