-- =============================================================================
-- seg7_decoder.vhd
-- 7-Segment Display Decoder (active-low, common-anode, DE10-Lite)
--
-- Converts a 4-bit hex digit (0x0–0xF) into the 8-bit active-low segment
-- pattern for the MAX10 DE10-Lite on-board displays.
--
-- Segment bit mapping:
--   bit 7 = DP (decimal point — always off here)
--   bit 6 = G  (middle bar)
--   bit 5 = F  (upper-left)
--   bit 4 = E  (lower-left)
--   bit 3 = D  (bottom)
--   bit 2 = C  (lower-right)
--   bit 1 = B  (upper-right)
--   bit 0 = A  (top)
--
-- Output is purely combinational — no clock required.
-- Instantiate once per display digit.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity seg7_decoder is
    port (
        digit : in  std_logic_vector(3 downto 0);  -- Hex value 0x0–0xF
        seg   : out std_logic_vector(7 downto 0)   -- Active-low segments
    );
end entity seg7_decoder;

architecture rtl of seg7_decoder is
begin

    p_decode : process (digit)
    begin
        case digit is
            --                  DP GFEDCBA
            when x"0"   => seg <= "11000000";  -- 0
            when x"1"   => seg <= "11111001";  -- 1
            when x"2"   => seg <= "10100100";  -- 2
            when x"3"   => seg <= "10110000";  -- 3
            when x"4"   => seg <= "10011001";  -- 4
            when x"5"   => seg <= "10010010";  -- 5
            when x"6"   => seg <= "10000010";  -- 6
            when x"7"   => seg <= "11111000";  -- 7
            when x"8"   => seg <= "10000000";  -- 8
            when x"9"   => seg <= "10010000";  -- 9
            when x"A"   => seg <= "10001000";  -- A
            when x"B"   => seg <= "10000011";  -- b
            when x"C"   => seg <= "11000110";  -- C
            when x"D"   => seg <= "10100001";  -- d
            when x"E"   => seg <= "10000110";  -- E
            when x"F"   => seg <= "10001110";  -- F
            when others => seg <= "11111111";  -- all off
        end case;
    end process p_decode;

end architecture rtl;
