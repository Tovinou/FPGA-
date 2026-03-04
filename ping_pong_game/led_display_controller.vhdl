-------------------------------------------------------------------------------
-- Module: LED Display Controller for DE10-Lite
-- Uses all 10 user LEDs (LEDR0-LEDR9)
-- Handles menu, match-over, not-started, and active gameplay modes
-------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

entity led_display_controller is
    generic (
        freq       : integer := 50000000  -- system clock frequency (Hz)
        --led_num    : integer := 10         -- number of LEDs on DE10-Lite
    );
    port (
        clk             : in  std_logic;
        reset           : in  std_logic;

        -- Game state
        game_mode       : in  integer range 0 to 2;
        game_started    : in  std_logic;
        match_over      : in  std_logic;
        difficulty      : in  integer range 0 to 3;

        -- Ball and power-up
        ball_position   : in  integer range 0 to 9;
        powerup_active  : in  std_logic;
        powerup_position: in  integer range 0 to 9;

        -- LED output (active HIGH)
        led             : out std_logic_vector(9 downto 0)
    );
end led_display_controller;

architecture rtl of led_display_controller is
    -- 32-bit counter to avoid overflow during long runs
    signal animation_counter : unsigned(31 downto 0) := (others => '0');
begin

    process(clk, reset)
        variable led_temp : std_logic_vector(9 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                led <= (others => '0');
                animation_counter <= (others => '0');
            else
                -- Increment animation counter
                animation_counter <= animation_counter + 1;
                led_temp := (others => '0');

                -- Menu mode: display difficulty level as leading LEDs
                if game_mode = 0 then
                    case difficulty is
                        when 0 => led_temp := "1000000000";
                        when 1 => led_temp := "1100000000";
                        when 2 => led_temp := "1110000000";
                        when 3 => led_temp := "1111000000";
                        when others => led_temp := (others => '0');
                    end case;

                -- Match-over celebration: blink all LEDs at 1 Hz
                elsif match_over = '1' then
                    if animation_counter mod (freq/2) < (freq/4) then
                        led_temp := (others => '1');
                    else
                        led_temp := (others => '0');
                    end if;

                -- Game not started: light only the first LED
                elsif game_started = '0' then
                    led_temp(9) := '1';

                -- Active gameplay: ball and optional power-up
                else
                    -- Light the ball
                    led_temp(ball_position) := '1';

                    -- Flash power-up every 1 ms
                    if powerup_active = '1' and animation_counter mod 2000 < 1000 then
                        led_temp(powerup_position) := '1';
                    end if;
                end if;

                -- Update output
                led <= led_temp;
            end if;
        end if;
    end process;

end rtl;
