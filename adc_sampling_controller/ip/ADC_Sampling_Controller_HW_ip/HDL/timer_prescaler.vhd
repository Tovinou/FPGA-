LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

-- Prescaler: Divides clock by 1, 2, 4, 8, 16, 32, 64, or 128
-- Generates a single-cycle pulse at the divided frequency
ENTITY timer_prescaler IS
   PORT (
      clk           : IN std_logic;
      reset_n       : IN std_logic;
      prescaler_sel : IN std_logic_vector(2 downto 0);  -- Selection: 000-111
      clock_enable  : OUT std_logic                     -- Single-cycle pulse output
   );
END timer_prescaler;

ARCHITECTURE rtl OF timer_prescaler IS
   SIGNAL prescaler_cnt : unsigned(6 downto 0) := (others => '0');
   SIGNAL prescaler_max : unsigned(6 downto 0);
   SIGNAL phase_cnt     : std_logic := '1';
   SIGNAL prev_sel      : std_logic_vector(2 downto 0) := (others => '0');
   
BEGIN

   -- Prescaler calculation
   prescaler_max <= to_unsigned(0, 7) when prescaler_sel = "000" else    -- div 1
                   to_unsigned(1, 7) when prescaler_sel = "001" else    -- div 2
                   to_unsigned(3, 7) when prescaler_sel = "010" else    -- div 4
                   to_unsigned(7, 7) when prescaler_sel = "011" else    -- div 8
                   to_unsigned(15, 7) when prescaler_sel = "100" else   -- div 16
                   to_unsigned(31, 7) when prescaler_sel = "101" else   -- div 32
                   to_unsigned(63, 7) when prescaler_sel = "110" else   -- div 64
                   to_unsigned(127, 7);                                  -- div 128

   -- Counter process
   Prescaler_counter : PROCESS(clk, reset_n)
   BEGIN
      if reset_n = '0' then
         prescaler_cnt <= (others => '0');
         clock_enable <= '0';
         phase_cnt <= '1';
         prev_sel <= (others => '0');
      elsif rising_edge(clk) then
         if prescaler_sel /= prev_sel then
            prescaler_cnt <= (others => '0');
            phase_cnt <= '1';
            prev_sel <= prescaler_sel;
            if prescaler_sel = "000" then
               clock_enable <= '1';
            else
               clock_enable <= '0';
            end if;
         elsif prescaler_sel = "000" then
            prescaler_cnt <= (others => '0');
            clock_enable <= '1';
            phase_cnt <= '0';
         elsif prescaler_cnt = prescaler_max then
            prescaler_cnt <= (others => '0');
            if phase_cnt = '1' then
               clock_enable <= '1';
               phase_cnt <= '0';
            else
               clock_enable <= '0';
               phase_cnt <= '1';
            end if;
         else
            prescaler_cnt <= prescaler_cnt + 1;
            clock_enable <= '0';
         end if;
      end if;
   END PROCESS Prescaler_counter;

END rtl;
