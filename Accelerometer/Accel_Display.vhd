library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Accel_Display is
   Port 
	   (
      clk         : in  STD_LOGIC;                    -- System clock
      reset_n     : in  STD_LOGIC;                    -- Active low asynchronous reset
      i_accel_x   : in  STD_LOGIC_VECTOR (15 downto 0);  -- 16-bit signed X-axis acceleration
      i_accel_y   : in  STD_LOGIC_VECTOR (15 downto 0);  -- 16-bit signed Y-axis acceleration
      i_accel_z   : in  STD_LOGIC_VECTOR (15 downto 0);  -- 16-bit signed Z-axis acceleration        
      o_hex0      : out STD_LOGIC_VECTOR (6 downto 0);  -- 7-segment display for X-axis value
      o_hex1      : out STD_LOGIC_VECTOR (6 downto 0);  -- 7-segment display for Y-axis value
      o_hex2      : out STD_LOGIC_VECTOR (6 downto 0)   -- 7-segment display for Z-axis value
      );
end Accel_Display;

architecture Behavioral of Accel_Display is
   signal abs_acc_x_int : integer;  -- Intermediate signal for absolute value
   signal abs_acc_y_int : integer;
   signal abs_acc_z_int : integer;
   signal abs_acc_x     : unsigned(15 downto 0);
   signal abs_acc_y     : unsigned(15 downto 0);
   signal abs_acc_z     : unsigned(15 downto 0);
   signal digit_x       : unsigned(3 downto 0);  -- 4 bits to hold values 0-9
   signal digit_y       : unsigned(3 downto 0);
   signal digit_z       : unsigned(3 downto 0);

begin

   process (clk, reset_n)
   begin
      if reset_n = '0' then
         abs_acc_x <= (others => '0');
         abs_acc_y <= (others => '0');
         abs_acc_z <= (others => '0');
         digit_x <= (others => '0');
         digit_y <= (others => '0');
         digit_z <= (others => '0');
         o_hex0 <= "1111111";  -- Blank display
         o_hex1 <= "1111111";  -- Blank display
         o_hex2 <= "1111111";  -- Blank display
      elsif rising_edge(clk) then
         -- Calculate absolute values of acceleration vectors
         abs_acc_x_int <= abs(to_integer(signed(i_accel_x)));
         abs_acc_y_int <= abs(to_integer(signed(i_accel_y)));
         abs_acc_z_int <= abs(to_integer(signed(i_accel_z)));

         -- Convert integer absolute values to unsigned
         abs_acc_x <= to_unsigned(abs_acc_x_int, 16);
         abs_acc_y <= to_unsigned(abs_acc_y_int, 16);
         abs_acc_z <= to_unsigned(abs_acc_z_int, 16);

         -- Extract the least significant digit for each axis
         digit_x <= abs_acc_x(3 downto 0);  -- Extracts the unit place
         digit_y <= abs_acc_y(3 downto 0);  -- Extracts the unit place
         digit_z <= abs_acc_z(3 downto 0);  -- Extracts the unit place

         -- Mapping for X-axis digit
         case digit_x is
            when "0000" => o_hex0 <= "1000000";
            when "0001" => o_hex0 <= "1111001";
            when "0010" => o_hex0 <= "0100100";
            when "0011" => o_hex0 <= "0110000";
            when "0100" => o_hex0 <= "0011001";
            when "0101" => o_hex0 <= "0010010";
            when "0110" => o_hex0 <= "0000010";
            when "0111" => o_hex0 <= "1111000";
            when "1000" => o_hex0 <= "0000000";
            when "1001" => o_hex0 <= "0011000";
            when others => o_hex0 <= "1111111";  -- Blank display for invalid values
         end case;

         -- Mapping for Y-axis digit
         case digit_y is
            when "0000" => o_hex1 <= "1000000";
            when "0001" => o_hex1 <= "1111001";
            when "0010" => o_hex1 <= "0100100";
            when "0011" => o_hex1 <= "0110000";
            when "0100" => o_hex1 <= "0011001";
            when "0101" => o_hex1 <= "0010010";
            when "0110" => o_hex1 <= "0000010";
            when "0111" => o_hex1 <= "1111000";
            when "1000" => o_hex1 <= "0000000";
            when "1001" => o_hex1 <= "0011000";
            when others => o_hex1 <= "1111111";  -- Blank display for invalid values
         end case;

         -- Mapping for Z-axis digit
         case digit_z is
            when "0000" => o_hex2 <= "1000000";
            when "0001" => o_hex2 <= "1111001";
            when "0010" => o_hex2 <= "0100100";
            when "0011" => o_hex2 <= "0110000";
            when "0100" => o_hex2 <= "0011001";
            when "0101" => o_hex2 <= "0010010";
            when "0110" => o_hex2 <= "0000010";
            when "0111" => o_hex2 <= "1111000";
            when "1000" => o_hex2 <= "0000000";
            when "1001" => o_hex2 <= "0011000";
            when others => o_hex2 <= "1111111";  -- Blank display for invalid values
         end case;        
      end if;
   end process;   

end Behavioral;
