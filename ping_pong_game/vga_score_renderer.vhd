-- FIX: user1_score / user2_score range changed from (0 to 3) to (0 to 9)
--      to match the game_state_manager output and top-level signal.
--      Score display now shows value 0-4 (game uses max 4 points per round).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_score_renderer is
    port(
        clk         : in  std_logic;
        resetn      : in  std_logic;
        user1_score : in  integer range 0 to 9;   -- FIX: was 0 to 3
        user2_score : in  integer range 0 to 9;   -- FIX: was 0 to 3
        anim_state  : in  integer range 0 to 3;

        x_counter   : in  unsigned(9 downto 0);
        y_counter   : in  unsigned(9 downto 0);

        rgb_out     : out std_logic_vector(2 downto 0)
    );
end entity;

architecture rtl of vga_score_renderer is
    constant ZONE_WIDTH  : integer := 100;
    constant ZONE_HEIGHT : integer := 100;

    constant X_USER1 : integer := 50;
    constant X_DASH  : integer := 270;
    constant X_USER2 : integer := 490;
    constant Y_BASE  : integer := 50;

    -- Helper: map score 0-4 to a color
    function score_to_color(s : integer) return std_logic_vector is
    begin
        case s is
            when 0      => return "100"; -- red    (0 points)
            when 1      => return "110"; -- yellow (1 point)
            when 2      => return "010"; -- green  (2 points)
            when 3      => return "011"; -- cyan   (3 points)
            when 4      => return "111"; -- white  (4 points = round won)
            when others => return "100";
        end case;
    end function;

begin
    process(clk)
        variable color : std_logic_vector(2 downto 0);
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                rgb_out <= "000";
            else
                color := "000";

                -- USER1 score block (left side)
                if to_integer(x_counter) >= X_USER1 and to_integer(x_counter) < X_USER1+ZONE_WIDTH and
                   to_integer(y_counter) >= Y_BASE  and to_integer(y_counter) < Y_BASE+ZONE_HEIGHT then
                    color := score_to_color(user1_score);
                end if;

                -- USER2 score block (right side)
                if to_integer(x_counter) >= X_USER2 and to_integer(x_counter) < X_USER2+ZONE_WIDTH and
                   to_integer(y_counter) >= Y_BASE  and to_integer(y_counter) < Y_BASE+ZONE_HEIGHT then
                    color := score_to_color(user2_score);
                end if;

                -- Dash separator (flashes based on animation state)
                if to_integer(x_counter) >= X_DASH and to_integer(x_counter) < X_DASH+ZONE_WIDTH and
                   to_integer(y_counter) >= Y_BASE  and to_integer(y_counter) < Y_BASE+ZONE_HEIGHT then
                    if anim_state = 0 or anim_state = 3 then
                        color := "111";
                    else
                        color := "000";
                    end if;
                end if;

                rgb_out <= color;
            end if;
        end if;
    end process;
end rtl;
