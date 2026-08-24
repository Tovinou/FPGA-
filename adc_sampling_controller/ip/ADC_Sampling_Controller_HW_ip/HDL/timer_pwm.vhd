LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

-- Timer PWM: Generates PWM output based on timer and compare values
-- PWM output = 1 when timer < compare_value, else 0
ENTITY timer_pwm IS
   GENERIC (
      TIMER_WIDTH : integer := 32
   );
   PORT (
      clk           : IN std_logic;
      reset_n       : IN std_logic;
      pwm_enable    : IN std_logic;
      
      timer_value   : IN std_logic_vector(TIMER_WIDTH-1 downto 0);
      compare_value : IN std_logic_vector(TIMER_WIDTH-1 downto 0);
      
      pwm_out       : OUT std_logic
   );
END timer_pwm;

ARCHITECTURE rtl OF timer_pwm IS
BEGIN

   pwm_out <= '1'
      when reset_n = '1' and pwm_enable = '1' and unsigned(timer_value) < unsigned(compare_value)
      else '0';

END rtl;
