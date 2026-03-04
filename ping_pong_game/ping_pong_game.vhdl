-------------------------------------------------------------------------------
-- TOP MODULE: Ping Pong Game Top (DE10-Lite, 10 LEDs)
-- FIXED:
--   1. SW port corrected to (9 downto 0) to match DE10-Lite
--   2. GPIO_0 replaced by GPIO(0) pin from the 36-bit GPIO bus
--   3. user1_score/user2_score signal range fixed to match game_state_manager (0 to 9)
--   4. x_counter / y_counter now driven from vga_controller outputs
--   5. anim_state_int now exported from seven_seg_controller
--   6. resetn internal signal added (cannot use "not signal" directly in port map)
--   7. PLL entity name stray space removed
--   8. goal_scored_sig intermediate signal added (no expressions in port maps)
-------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;

entity ping_pong_game is
generic (
    freq               : integer := 50000000;
    slow_clk_nb_cycles : integer := 249999
);
port (
    SW            : in    std_logic_vector(9 downto 0);    -- FIX 1
    MAX10_CLK1_50 : in    std_logic;
    LEDR          : out   std_logic_vector(9 downto 0);
    HEX0          : out   std_logic_vector(7 downto 0);
    HEX1          : out   std_logic_vector(7 downto 0);
    HEX2          : out   std_logic_vector(7 downto 0);
    HEX3          : out   std_logic_vector(7 downto 0);
    HEX4          : out   std_logic_vector(7 downto 0);
    HEX5          : out   std_logic_vector(7 downto 0);
    GPIO          : inout std_logic_vector(35 downto 0);   -- FIX 2
    VGA_HS        : out   std_logic;
    VGA_VS        : out   std_logic;
    VGA_R         : out   std_logic_vector(3 downto 0);
    VGA_G         : out   std_logic_vector(3 downto 0);
    VGA_B         : out   std_logic_vector(3 downto 0)
);
end ping_pong_game;

architecture structural of ping_pong_game is

    signal reset  : std_logic;
    signal resetn : std_logic;  -- FIX 6: active-low reset for VGA modules

    signal btnl, btnr, btnup_sig, btndown_sig : std_logic;
    signal btnl_debnc, btnr_debnc, btnup_debnc, btndown_debnc : std_logic;
    signal btnl_pulse, btnr_pulse, btnup_pulse, btndown_pulse : std_logic;
    signal btnl_debnc_r, btnr_debnc_r, btnup_debnc_r, btndown_debnc_r : std_logic := '0';

    signal game_mode  : integer range 0 to 2;
    signal difficulty : integer range 0 to 3;
    signal game_started, game_paused, round_over, match_over : std_logic;

    signal user1_score, user2_score   : integer range 0 to 9;  -- FIX 3
    signal user1_rounds, user2_rounds : integer range 0 to 3;

    signal ball_position : integer range 0 to 9;
    signal direction     : std_logic;
    signal score_user1, score_user2, ball_hit : std_logic;
    signal rebound_counter, combo_counter : integer range 0 to 15;

    signal powerup_active    : std_logic;
    signal powerup_position  : integer range 0 to 9;
    signal powerup_type      : integer range 0 to 2;
    signal powerup_collected : std_logic;

    signal round_complete   : std_logic;
    signal pause_timer      : integer := 0;
    constant PAUSE_TIME     : integer := freq;

    signal vga_data       : std_logic_vector(2 downto 0);
    signal x_counter      : unsigned(9 downto 0);  -- FIX 4
    signal y_counter      : unsigned(9 downto 0);  -- FIX 4
    signal anim_state_int : integer range 0 to 3;  -- FIX 5
    signal clk_25         : std_logic;
    signal goal_scored_sig : std_logic;             -- FIX 8

begin

    reset          <= not SW(9);
    resetn         <= SW(9);   -- FIX 6
    btnl           <= not SW(8);
    btnr           <= not SW(7);
    btnup_sig      <= not SW(6);
    btndown_sig    <= not SW(5);
    goal_scored_sig <= score_user1 or score_user2;  -- FIX 8

    process(MAX10_CLK1_50)
    begin
        if rising_edge(MAX10_CLK1_50) then
            btnl_debnc_r    <= btnl_debnc;
            btnr_debnc_r    <= btnr_debnc;
            btnup_debnc_r   <= btnup_debnc;
            btndown_debnc_r <= btndown_debnc;

            btnl_pulse    <= btnl_debnc    and not btnl_debnc_r;
            btnr_pulse    <= btnr_debnc    and not btnr_debnc_r;
            btnup_pulse   <= btnup_debnc   and not btnup_debnc_r;
            btndown_pulse <= btndown_debnc and not btndown_debnc_r;
        end if;
    end process;

    process(MAX10_CLK1_50)
    begin
        if rising_edge(MAX10_CLK1_50) then
            if reset = '1' then
                pause_timer    <= 0;
                round_complete <= '0';
            else
                round_complete <= '0';
                if game_paused = '1' then
                    if pause_timer >= PAUSE_TIME then
                        if (ball_position = 0 and btnr_pulse = '1') or
                           (ball_position = 9 and btnl_pulse = '1') then
                            round_complete <= '1';
                            pause_timer    <= 0;
                        end if;
                    else
                        pause_timer <= pause_timer + 1;
                    end if;
                else
                    pause_timer <= 0;
                end if;
            end if;
        end if;
    end process;

    -- PLL: 50 MHz -> 25 MHz for VGA
    bdnc_pll : entity work.pll  -- FIX 7: removed stray space
        port map (
            inclk0 => MAX10_CLK1_50,
            c0     => clk_25
        );

    dbnc_btn_left : entity work.debounce_button
        generic map (slow_clk_nb_cycles => slow_clk_nb_cycles)
        port map (clk => MAX10_CLK1_50, reset => reset, button => btnl, debounce_button => btnl_debnc);

    dbnc_btn_right : entity work.debounce_button
        generic map (slow_clk_nb_cycles => slow_clk_nb_cycles)
        port map (clk => MAX10_CLK1_50, reset => reset, button => btnr, debounce_button => btnr_debnc);

    dbnc_btn_up : entity work.debounce_button
        generic map (slow_clk_nb_cycles => slow_clk_nb_cycles)
        port map (clk => MAX10_CLK1_50, reset => reset, button => btnup_sig, debounce_button => btnup_debnc);

    dbnc_btn_down : entity work.debounce_button
        generic map (slow_clk_nb_cycles => slow_clk_nb_cycles)
        port map (clk => MAX10_CLK1_50, reset => reset, button => btndown_sig, debounce_button => btndown_debnc);

    game_state_mgr : entity work.game_state_manager
        generic map (freq => freq)
        port map (
            clk => MAX10_CLK1_50, reset => reset,
            btnl_pulse => btnl_pulse, btnr_pulse => btnr_pulse,
            btnup_pulse => btnup_pulse, btndown_pulse => btndown_pulse,
            game_mode => game_mode, difficulty => difficulty,
            game_started => game_started, game_paused => game_paused,
            round_over => round_over, match_over => match_over,
            user1_score => user1_score, user2_score => user2_score,
            user1_rounds => user1_rounds, user2_rounds => user2_rounds,
            score_user1 => score_user1, score_user2 => score_user2,
            round_complete => round_complete
        );

    ball_engine : entity work.ball_physics
        generic map (freq => freq)
        port map (
            clk => MAX10_CLK1_50, reset => reset,
            game_started => game_started, game_paused => game_paused,
            difficulty => difficulty,
            btnl_pulse => btnl_pulse, btnr_pulse => btnr_pulse,
            ball_position => ball_position, direction => direction,
            score_user1 => score_user1, score_user2 => score_user2,
            ball_hit => ball_hit,
            rebound_counter => rebound_counter, combo_counter => combo_counter
        );

    powerup_ctrl : entity work.powerup_controller
        port map (
            clk => MAX10_CLK1_50, reset => reset,
            game_started => game_started, game_paused => game_paused,
            rebound_counter => rebound_counter, ball_position => ball_position,
            powerup_active => powerup_active, powerup_position => powerup_position,
            powerup_type => powerup_type, powerup_collected => powerup_collected
        );

    sound_gen : entity work.sound_generator
        port map (
            clk => MAX10_CLK1_50, reset => reset,
            ball_hit => ball_hit, goal_scored => goal_scored_sig,  -- FIX 8
            powerup_collected => powerup_collected,
            match_won => match_over,
            speaker => GPIO(0)   -- FIX 2
        );

    led_ctrl : entity work.led_display_controller
        generic map (freq => freq)
        port map (
            clk => MAX10_CLK1_50, reset => reset,
            game_mode => game_mode, game_started => game_started,
            match_over => match_over, difficulty => difficulty,
            ball_position => ball_position,
            powerup_active => powerup_active, powerup_position => powerup_position,
            led => LEDR
        );

    seg_ctrl : entity work.seven_seg_controller
        generic map (slow_clk_nb_cycles => slow_clk_nb_cycles)
        port map (
            clk => MAX10_CLK1_50, reset => reset,
            user1_score => user1_score, user2_score => user2_score,
            anim_state => anim_state_int,   -- FIX 5
            HEX0 => HEX0, HEX1 => HEX1, HEX2 => HEX2,
            HEX3 => HEX3, HEX4 => HEX4, HEX5 => HEX5
        );

    vga_renderer : entity work.vga_score_renderer
        port map (
            clk => clk_25, resetn => resetn,   -- FIX 6
            user1_score => user1_score, user2_score => user2_score,
            anim_state => anim_state_int,
            x_counter => x_counter,  -- FIX 4
            y_counter => y_counter,  -- FIX 4
            rgb_out => vga_data
        );

    vga_ctrl_inst : entity work.vga_controller
        port map (
            clk_25 => clk_25, resetn => resetn,  -- FIX 6
            rgb_in => vga_data,
            vga_r => VGA_R, vga_g => VGA_G, vga_b => VGA_B,
            hsync => VGA_HS, vsync => VGA_VS,
            x_counter => x_counter,  -- FIX 4
            y_counter => y_counter   -- FIX 4
        );

end structural;
