LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

-- Timer Counter: Handles count up/down logic
-- Supports load, reset, start/stop, and overflow detection
ENTITY timer_counter IS
   GENERIC (
      TIMER_WIDTH : integer := 32
   );
   PORT (
      clk           : IN std_logic;
      reset_n       : IN std_logic;
      clock_enable  : IN std_logic;              -- Prescaler output
      
      -- Control signals
      timer_start   : IN std_logic;
      timer_stop    : IN std_logic;
      timer_reset   : IN std_logic;
      timer_load    : IN std_logic;
      countdown_en  : IN std_logic;              -- 1 = countdown, 0 = countup
      
      -- Data ports
      load_value    : IN std_logic_vector(TIMER_WIDTH-1 downto 0);
      timer_value   : OUT std_logic_vector(TIMER_WIDTH-1 downto 0);
      
      -- Status outputs
      running       : OUT std_logic;
      overflow      : OUT std_logic
   );
END timer_counter;

ARCHITECTURE rtl OF timer_counter IS
   SIGNAL count_reg       : unsigned(TIMER_WIDTH-1 downto 0) := (others => '0');
   SIGNAL running_flag    : std_logic := '0';
   SIGNAL overflow_flag   : std_logic := '0';
   SIGNAL timer_max       : unsigned(TIMER_WIDTH-1 downto 0);
   SIGNAL next_running    : std_logic;  -- Next state of running_flag
   
BEGIN

   timer_max <= (others => '1');  -- All 1s (maximum value for given width)

   -- Compute next running state based on commands
   -- Commands have priority: reset/load > stop > start
   next_running <= '0' when (timer_reset = '1' or timer_load = '1' or timer_stop = '1') else
                   '1' when (timer_start = '1' and running_flag = '0') else
                   running_flag;

   -- Main counter process
   Counter_process : PROCESS(clk, reset_n)
      VARIABLE should_count : std_logic;
   BEGIN
      if reset_n = '0' then
         count_reg <= (others => '0');
         running_flag <= '0';
         overflow_flag <= '0';
         
      elsif rising_edge(clk) then
         -- Determine if we should count this cycle using current/next running state
         -- Use combinational logic to avoid pipeline delays
         should_count := '0';
         if timer_reset = '1' or timer_load = '1' then
            should_count := '0';  -- Inhibit counting when loading/resetting
         elsif timer_stop = '1' then
            should_count := '0';  -- Inhibit counting when stopping
         elsif timer_start = '1' or running_flag = '1' then
            should_count := clock_enable;  -- Count if clock enabled and (starting or already running)
         end if;

         -- Handle command execution
         if timer_load = '1' then
            count_reg <= unsigned(load_value);
            overflow_flag <= '0';
            running_flag <= '0';
         elsif timer_reset = '1' then
            count_reg <= (others => '0');
            overflow_flag <= '0';
            running_flag <= '0';
         elsif timer_start = '1' and running_flag = '0' then
            running_flag <= '1';
         elsif timer_stop = '1' then
            running_flag <= '0';
         elsif should_count = '1' then
            -- Counter logic - only execute if should_count is true
            if countdown_en = '1' then
               -- Countdown mode
               if count_reg = 0 then
                  overflow_flag <= '1';
                  count_reg <= timer_max;
               else
                  count_reg <= count_reg - 1;
               end if;
            else
               -- Countup mode (default)
               if count_reg = timer_max then
                  overflow_flag <= '1';
                  count_reg <= (others => '0');
               else
                  count_reg <= count_reg + 1;
               end if;
            end if;
         end if;
      end if;
   END PROCESS Counter_process;

   -- Output assignments
   timer_value <= std_logic_vector(count_reg);
   running <= running_flag;
   overflow <= overflow_flag;

END rtl;
