--------------------------------------------------------------------------------
-- seg7_decoder.vhd
--
-- Simple 4-bit binary -> 7-segment (active-low, DE10-Lite style) decoder.
-- Segment bit order matches the DE10-Lite HEXn[6:0] convention:
--   bit0=a(top), bit1=b(upper-right), bit2=c(lower-right), bit3=d(bottom),
--   bit4=e(lower-left), bit5=f(upper-left), bit6=g(middle). Active-low.
-- bit7 (decimal point) is left unused/off ('1').
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;

entity seg7_decoder is
   port (
      hex_in : in  std_logic_vector(3 downto 0);
      seg_out: out std_logic_vector(7 downto 0)  -- [7]=dp (off), [6:0]=g..a
   );
end entity seg7_decoder;

architecture rtl of seg7_decoder is
begin
   process(hex_in)
   begin
      seg_out(7) <= '1'; -- decimal point off
      case hex_in is
         when "0000" => seg_out(6 downto 0) <= "1000000"; -- 0
         when "0001" => seg_out(6 downto 0) <= "1111001"; -- 1
         when "0010" => seg_out(6 downto 0) <= "0100100"; -- 2
         when "0011" => seg_out(6 downto 0) <= "0110000"; -- 3
         when "0100" => seg_out(6 downto 0) <= "0011001"; -- 4
         when "0101" => seg_out(6 downto 0) <= "0010010"; -- 5
         when "0110" => seg_out(6 downto 0) <= "0000010"; -- 6
         when "0111" => seg_out(6 downto 0) <= "1111000"; -- 7
         when "1000" => seg_out(6 downto 0) <= "0000000"; -- 8
         when "1001" => seg_out(6 downto 0) <= "0010000"; -- 9
         when "1010" => seg_out(6 downto 0) <= "0001000"; -- A
         when "1011" => seg_out(6 downto 0) <= "0000011"; -- b
         when "1100" => seg_out(6 downto 0) <= "1000110"; -- C
         when "1101" => seg_out(6 downto 0) <= "0100001"; -- d
         when "1110" => seg_out(6 downto 0) <= "0000110"; -- E
         when others => seg_out(6 downto 0) <= "0001110"; -- F
      end case;
   end process;
end architecture rtl;
