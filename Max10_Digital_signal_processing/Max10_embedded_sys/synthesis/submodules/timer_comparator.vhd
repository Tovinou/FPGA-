LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

-- Timer Comparator: Generates interrupt when counter matches compare value
ENTITY timer_comparator IS
   GENERIC (
      TIMER_WIDTH : integer := 32
   );
   PORT (
      clk           : IN std_logic;
      reset_n       : IN std_logic;
      
      timer_value   : IN std_logic_vector(TIMER_WIDTH-1 downto 0);
      compare_value : IN std_logic_vector(TIMER_WIDTH-1 downto 0);
      
      compare_flag  : OUT std_logic;
      compare_int   : OUT std_logic
   );
END timer_comparator;

ARCHITECTURE rtl OF timer_comparator IS
   SIGNAL match_now       : std_logic;
   SIGNAL prev_match      : std_logic := '0';
   
BEGIN
   match_now <= '1' when unsigned(timer_value) = unsigned(compare_value) else '0';

   -- Compare process
   Compare_process : PROCESS(clk, reset_n)
   BEGIN
      if reset_n = '0' then
         prev_match <= '0';
         
      elsif rising_edge(clk) then
         prev_match <= match_now;
      end if;
   END PROCESS Compare_process;

   -- Outputs
   compare_flag <= match_now;
   compare_int <= match_now and not prev_match;

END rtl;
