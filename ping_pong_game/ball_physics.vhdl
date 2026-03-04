-------------------------------------------------------------------------------
-- Module 3: Ball Physics Engine for DE10-Lite
-- 10 LEDs (LEDR0-LEDR9)
-------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

entity ball_physics is
generic (
    freq : integer := 50000000  -- system clock frequency
);
port (
    clk : in std_logic;
    reset : in std_logic;

    -- Game control
    game_started : in std_logic;
    game_paused  : in std_logic;
    difficulty   : in integer range 0 to 3;

    -- Button inputs
    btnl_pulse : in std_logic;
    btnr_pulse : in std_logic;

    -- Ball state
    ball_position : out integer range 0 to 9;
    direction     : out std_logic; -- 0 = left_to_right, 1 = right_to_left

    -- Game events
    score_user1 : out std_logic;
    score_user2 : out std_logic;
    ball_hit    : out std_logic;

    -- Speed control
    rebound_counter : out integer range 0 to 15;
    combo_counter   : out integer range 0 to 15
);
end ball_physics;

architecture rtl of ball_physics is

    type t_game_speed_rom is array (0 to 5) of integer;
    constant game_speed_rom : t_game_speed_rom := (
        freq,
        integer(real(freq) * 0.75),
        integer(real(freq) * 0.60),
        integer(real(freq) * 0.45),
        integer(real(freq) * 0.35),
        integer(real(freq) * 0.25)
    );

    -- Internal signals
    signal ball_position_i : integer range 0 to 9 := 9;
    signal direction_i     : std_logic := '0';
    signal game_counter    : integer := 0;
    signal game_speed      : integer := freq;
    signal speed_level     : integer range 0 to 5 := 0;
    signal rebound_counter_i : integer range 0 to 15 := 0;
    signal combo_counter_i   : integer range 0 to 15 := 0;

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                ball_position_i <= 9;
                direction_i     <= '0';
                game_counter    <= 0;
                speed_level     <= 0;
                rebound_counter_i <= 0;
                combo_counter_i   <= 0;
                score_user1     <= '0';
                score_user2     <= '0';
                ball_hit        <= '0';
            else
                score_user1 <= '0';
                score_user2 <= '0';
                ball_hit    <= '0';

                if game_started = '1' and game_paused = '0' then
                    -- Set speed based on difficulty
                    case difficulty is
                        when 0 => game_speed <= game_speed_rom(0);
                        when 1 => game_speed <= game_speed_rom(1);
                        when 2 => game_speed <= game_speed_rom(2);
                        when 3 => game_speed <= game_speed_rom(3);
                        when others => game_speed <= game_speed_rom(0);
                    end case;

                    -- Game counter
                    if game_counter >= game_speed then
                        game_counter <= 0;
                    else
                        game_counter <= game_counter + 1;
                    end if;

                    -- Ball at left edge (position 0)
                    if ball_position_i = 0 and direction_i = '0' then
                        if game_counter >= game_speed then
                            score_user1 <= '1';
                            combo_counter_i <= 0;
                            direction_i <= '1';
                        elsif btnr_pulse = '1' then
                            rebound_counter_i <= rebound_counter_i + 1;
                            combo_counter_i <= combo_counter_i + 1;
                            direction_i <= '1';
                            ball_position_i <= 1;
                            ball_hit <= '1';
                        end if;

                    -- Ball at right edge (position 9)
                    elsif ball_position_i = 9 and direction_i = '1' then
                        if game_counter >= game_speed then
                            score_user2 <= '1';
                            combo_counter_i <= 0;
                            direction_i <= '0';
                        elsif btnl_pulse = '1' then
                            rebound_counter_i <= rebound_counter_i + 1;
                            combo_counter_i <= combo_counter_i + 1;
                            direction_i <= '0';
                            ball_position_i <= 8;
                            ball_hit <= '1';
                        end if;

                    -- Ball in middle
                    else
                        if game_counter >= game_speed then
                            if direction_i = '0' then
                                ball_position_i <= ball_position_i - 1;
                            else
                                ball_position_i <= ball_position_i + 1;
                            end if;
                        end if;
                    end if;

                    -- Speed progression
                    if rebound_counter_i > 0 and rebound_counter_i mod 3 = 0 then
                        if speed_level < 5 then
                            speed_level <= speed_level + 1;
                            game_speed <= game_speed_rom(speed_level + 1);
                        end if;
                    end if;

                else
                    -- Game paused or not started
                    game_counter <= 0;
                    if game_started = '0' then
                        ball_position_i <= 9;
                        direction_i <= '0';
                        rebound_counter_i <= 0;
                        combo_counter_i <= 0;
                        speed_level <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Output assignments
    ball_position <= ball_position_i;
    direction     <= direction_i;
    rebound_counter <= rebound_counter_i;
    combo_counter   <= combo_counter_i;

end rtl;
