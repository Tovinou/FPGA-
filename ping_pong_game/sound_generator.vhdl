-------------------------------------------------------------------------------
-- Module 5: Sound Generator
-------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;

entity sound_generator is
port (
    clk : in std_logic;
    reset : in std_logic;
    
    -- Sound triggers
    ball_hit : in std_logic;
    goal_scored : in std_logic;
    powerup_collected : in std_logic;
    match_won : in std_logic;
    
    -- Audio output
    speaker : out std_logic
);
end sound_generator;

architecture rtl of sound_generator is
    constant SOUND_HIT : integer := 1000;
    constant SOUND_GOAL : integer := 500;
    constant SOUND_WIN : integer := 2000;
    constant SOUND_POWERUP : integer := 1500;
    
    signal sound_active : std_logic := '0';
    signal sound_frequency : integer := 0;
    signal sound_duration : integer := 0;
    signal sound_counter : integer := 0;
    signal speaker_i : std_logic := '0';
begin

    process(clk, reset)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                sound_active <= '0';
                sound_counter <= 0;
                speaker_i <= '0';
            else
                -- Trigger sounds
                if ball_hit = '1' then
                    sound_active <= '1';
                    sound_frequency <= SOUND_HIT;
                    sound_duration <= 3000;
                elsif goal_scored = '1' then
                    sound_active <= '1';
                    sound_frequency <= SOUND_GOAL;
                    sound_duration <= 10000;
                elsif powerup_collected = '1' then
                    sound_active <= '1';
                    sound_frequency <= SOUND_POWERUP;
                    sound_duration <= 5000;
                elsif match_won = '1' then
                    sound_active <= '1';
                    sound_frequency <= SOUND_WIN;
                    sound_duration <= 15000;
                end if;
                
                -- Generate sound
                if sound_active = '1' then
                    if sound_duration > 0 then
                        sound_duration <= sound_duration - 1;
                        
                        if sound_counter >= sound_frequency then
                            sound_counter <= 0;
                            speaker_i <= not speaker_i;
                        else
                            sound_counter <= sound_counter + 1;
                        end if;
                    else
                        sound_active <= '0';
                        speaker_i <= '0';
                    end if;
                else
                    speaker_i <= '0';
                    sound_counter <= 0;
                end if;
            end if;
        end if;
    end process;
    
    speaker <= speaker_i;

end rtl;
