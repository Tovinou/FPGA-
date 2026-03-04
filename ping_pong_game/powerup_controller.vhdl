-------------------------------------------------------------------------------
-- Module 4: Power-up Controller (DE10-Lite, 10 LEDs)
-------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

entity powerup_controller is
port (
    clk : in std_logic;
    reset : in std_logic;

    -- Game state
    game_started : in std_logic;
    game_paused  : in std_logic;
    rebound_counter : in integer range 0 to 15;

    -- Ball info
    ball_position : in integer range 0 to 9;

    -- Power-up state
    powerup_active : out std_logic;
    powerup_position : out integer range 0 to 9;
    powerup_type : out integer range 0 to 2;
    powerup_collected : out std_logic
);
end powerup_controller;

architecture rtl of powerup_controller is
    signal powerup_active_i   : std_logic := '0';
    signal powerup_position_i : integer range 0 to 9 := 0;
    signal powerup_type_i     : integer range 0 to 2 := 0;
    signal spawn_counter      : integer := 0;
    signal rand_seed          : integer := 0;
begin

    process(clk, reset)
        variable rand_pos : integer range 0 to 9;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                powerup_active_i <= '0';
                powerup_collected <= '0';
                spawn_counter <= 0;
                rand_seed <= 0;
            else
                powerup_collected <= '0';
                rand_seed <= rand_seed + 1;

                if game_started = '1' and game_paused = '0' then

                    -- Spawn power-up every 5 rebounds
                    if powerup_active_i = '0' and rebound_counter > 0 and rebound_counter mod 5 = 0 then
                        -- Random position from 1 to 8 (avoid edges)
                        rand_pos := (rand_seed mod 8) + 1;
                        powerup_position_i <= rand_pos;
                        powerup_type_i <= rand_seed mod 3;
                        powerup_active_i <= '1';
                    end if;

                    -- Check collection
                    if powerup_active_i = '1' and ball_position = powerup_position_i then
                        powerup_collected <= '1';
                        powerup_active_i <= '0';
                    end if;

                else
                    powerup_active_i <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Output assignments
    powerup_active   <= powerup_active_i;
    powerup_position <= powerup_position_i;
    powerup_type     <= powerup_type_i;

end rtl;
