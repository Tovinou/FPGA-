-------------------------------------------------------------------------------
-- Seven Segment Display Controller for DE10-Lite
-- FIXED:
--   1. Added anim_state output port (integer range 0 to 3) so top-level can
--      pass animation state to vga_score_renderer
--   2. user1_score / user2_score range changed to 0 to 9 to match top-level
-------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

entity seven_seg_controller is
    generic (
        slow_clk_nb_cycles : integer := 12499999
    );
    port (
        clk : in std_logic;
        reset : in std_logic;

        user1_score : in integer range 0 to 9;   -- FIX 2
        user2_score : in integer range 0 to 9;   -- FIX 2

        anim_state  : out integer range 0 to 3;  -- FIX 1: new output

        HEX0 : out std_logic_vector(7 downto 0);
        HEX1 : out std_logic_vector(7 downto 0);
        HEX2 : out std_logic_vector(7 downto 0);
        HEX3 : out std_logic_vector(7 downto 0);
        HEX4 : out std_logic_vector(7 downto 0);
        HEX5 : out std_logic_vector(7 downto 0)
    );
end seven_seg_controller;

architecture rtl of seven_seg_controller is

    function bcd_decoder(n : integer) return std_logic_vector is
    begin
        case n is
            when 0      => return "11000000";
            when 1      => return "11111001";
            when 2      => return "10100100";
            when 3      => return "10110000";
            when 4      => return "10011001";
            when 5      => return "10010010";
            when 6      => return "10000010";
            when 7      => return "11111000";
            when 8      => return "10000000";
            when 9      => return "10010000";
            when others => return "11111111";
        end case;
    end function;

    constant minus_pattern : std_logic_vector(7 downto 0) := "11111110";

    type animation_state_type is (ANIM_HEX0, ANIM_HEX1, ANIM_HEX2, ANIM_HEX1_RETURN);
    signal anim_state_i : animation_state_type := ANIM_HEX0;

    signal slow_counter : integer range 0 to slow_clk_nb_cycles := 0;
    signal anim_tick    : std_logic := '0';

    signal user1_pattern : std_logic_vector(7 downto 0);
    signal user2_pattern : std_logic_vector(7 downto 0);

begin

    user1_pattern <= bcd_decoder(user1_score);
    user2_pattern <= bcd_decoder(user2_score);

    -- FIX 1: convert enum to integer for output
    anim_state <= 0 when anim_state_i = ANIM_HEX0 else
                  1 when anim_state_i = ANIM_HEX1 else
                  2 when anim_state_i = ANIM_HEX2 else
                  3;  -- ANIM_HEX1_RETURN

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                HEX0 <= (others => '1');
                HEX1 <= (others => '1');
                HEX2 <= (others => '1');
                HEX3 <= (others => '1');
                HEX4 <= (others => '1');
                HEX5 <= (others => '1');
                slow_counter <= 0;
                anim_tick    <= '0';
                anim_state_i <= ANIM_HEX0;
            else
                if slow_counter = slow_clk_nb_cycles then
                    slow_counter <= 0;
                    anim_tick    <= '1';
                else
                    slow_counter <= slow_counter + 1;
                    anim_tick    <= '0';
                end if;

                if anim_tick = '1' then
                    case anim_state_i is
                        when ANIM_HEX0        => anim_state_i <= ANIM_HEX1;
                        when ANIM_HEX1        => anim_state_i <= ANIM_HEX2;
                        when ANIM_HEX2        => anim_state_i <= ANIM_HEX1_RETURN;
                        when ANIM_HEX1_RETURN => anim_state_i <= ANIM_HEX0;
                    end case;
                end if;

                case anim_state_i is
                    when ANIM_HEX0 =>
                        HEX0 <= minus_pattern;
                        HEX1 <= (others => '1');
                        HEX2 <= user2_pattern;
                    when ANIM_HEX1 =>
                        HEX0 <= user1_pattern;
                        HEX1 <= minus_pattern;
                        HEX2 <= user2_pattern;
                    when ANIM_HEX2 =>
                        HEX0 <= user1_pattern;
                        HEX1 <= (others => '1');
                        HEX2 <= minus_pattern;
                    when ANIM_HEX1_RETURN =>
                        HEX0 <= user1_pattern;
                        HEX1 <= minus_pattern;
                        HEX2 <= user2_pattern;
                end case;

                HEX3 <= (others => '1');
                HEX4 <= (others => '1');
                HEX5 <= (others => '1');
            end if;
        end if;
    end process;

end rtl;
