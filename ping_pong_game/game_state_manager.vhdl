-------------------------------------------------------------------------------
-- Module 2: Game State Manager (DE10-Lite)
-- FIXED:
--   1. user1_score / user2_score output range changed to 0 to 9 for consistency
--      with top-level signal and display modules.
--      (Internally the score only reaches 4 before a round is awarded.)
-------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

entity game_state_manager is
generic (
    freq : integer := 50000000
);
port (
    clk   : in std_logic;
    reset : in std_logic;

    btnl_pulse    : in std_logic;
    btnr_pulse    : in std_logic;
    btnup_pulse   : in std_logic;
    btndown_pulse : in std_logic;

    game_mode    : out integer range 0 to 2;
    difficulty   : out integer range 0 to 3;
    game_started : out std_logic;
    game_paused  : out std_logic;
    round_over   : out std_logic;
    match_over   : out std_logic;

    user1_score  : out integer range 0 to 9;   -- FIX 1
    user2_score  : out integer range 0 to 9;   -- FIX 1
    user1_rounds : out integer range 0 to 3;
    user2_rounds : out integer range 0 to 3;

    score_user1    : in std_logic;
    score_user2    : in std_logic;
    round_complete : in std_logic
);
end game_state_manager;

architecture rtl of game_state_manager is
    signal game_mode_i    : integer range 0 to 2 := 0;
    signal difficulty_i   : integer range 0 to 3 := 1;
    signal game_started_i : std_logic := '0';
    signal game_paused_i  : std_logic := '0';
    signal round_over_i   : std_logic := '0';
    signal match_over_i   : std_logic := '0';

    signal user1_score_i  : integer range 0 to 9 := 0;  -- FIX 1
    signal user2_score_i  : integer range 0 to 9 := 0;  -- FIX 1
    signal user1_rounds_i : integer range 0 to 3 := 0;
    signal user2_rounds_i : integer range 0 to 3 := 0;
begin

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                game_mode_i    <= 0;
                difficulty_i   <= 1;
                game_started_i <= '0';
                game_paused_i  <= '0';
                round_over_i   <= '0';
                match_over_i   <= '0';
                user1_score_i  <= 0;
                user2_score_i  <= 0;
                user1_rounds_i <= 0;
                user2_rounds_i <= 0;
            else
                -- Menu
                if game_mode_i = 0 then
                    if btnup_pulse = '1' then
                        if difficulty_i < 3 then difficulty_i <= difficulty_i + 1;
                        else difficulty_i <= 0; end if;
                    end if;
                    if btndown_pulse = '1' then game_mode_i <= 1; end if;
                    if btnl_pulse   = '1' then game_mode_i <= 2; end if;
                end if;

                -- Start game
                if (game_mode_i = 1 or game_mode_i = 2) and
                   game_started_i = '0' and match_over_i = '0' then
                    if btnl_pulse = '1' or btnr_pulse = '1' then
                        game_started_i <= '1';
                        game_paused_i  <= '0';
                        round_over_i   <= '0';
                    end if;
                end if;

                -- Score management: first to 4 points wins round; first to 3 rounds wins match
                if score_user1 = '1' then
                    game_paused_i <= '1';
                    if user1_score_i >= 3 then   -- scoring the 4th point (was 4, off-by-one fix)
                        user1_rounds_i <= user1_rounds_i + 1;
                        round_over_i   <= '1';
                        user1_score_i  <= 0;
                        user2_score_i  <= 0;
                        if user1_rounds_i >= 2 then
                            match_over_i <= '1';
                        end if;
                    else
                        user1_score_i <= user1_score_i + 1;
                    end if;
                end if;

                if score_user2 = '1' then
                    game_paused_i <= '1';
                    if user2_score_i >= 3 then
                        user2_rounds_i <= user2_rounds_i + 1;
                        round_over_i   <= '1';
                        user1_score_i  <= 0;
                        user2_score_i  <= 0;
                        if user2_rounds_i >= 2 then
                            match_over_i <= '1';
                        end if;
                    else
                        user2_score_i <= user2_score_i + 1;
                    end if;
                end if;

                -- Resume after pause
                if round_complete = '1' then
                    game_paused_i <= '0';
                    round_over_i  <= '0';
                end if;

                -- Return to menu after match
                if match_over_i = '1' then
                    if btnl_pulse = '1' or btnr_pulse = '1' then
                        match_over_i   <= '0';
                        game_started_i <= '0';
                        game_mode_i    <= 0;
                        user1_rounds_i <= 0;
                        user2_rounds_i <= 0;
                        user1_score_i  <= 0;
                        user2_score_i  <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process;

    game_mode    <= game_mode_i;
    difficulty   <= difficulty_i;
    game_started <= game_started_i;
    game_paused  <= game_paused_i;
    round_over   <= round_over_i;
    match_over   <= match_over_i;
    user1_score  <= user1_score_i;
    user2_score  <= user2_score_i;
    user1_rounds <= user1_rounds_i;
    user2_rounds <= user2_rounds_i;

end rtl;
