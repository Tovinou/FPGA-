library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library vunit_lib;
context vunit_lib.vunit_context;

entity tb_debounce_explicit is
    generic (
        runner_cfg : string := runner_cfg_default
    );
end entity;

architecture tb of tb_debounce_explicit is
    constant clk_period : time := 20 ns;
    signal clk      : std_logic := '0';
    signal rst_n    : std_logic := '0';
    signal btn_in   : std_logic := '1';
    signal btn_out  : std_logic;
    signal btn_level: std_logic;
    signal pulse_count: integer := 0;
    signal pulse_count_clear : std_logic := '0';

    constant CLK_FREQ_HZ_c  : integer := 50_000_000;
    constant DEBOUNCE_MS_c  : integer := 20;
    constant DEBOUNCE_CYCLES_c : integer := (CLK_FREQ_HZ_c / 1000) * DEBOUNCE_MS_c;

    procedure tick(n: integer) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
    end procedure;
begin
    process
    begin
        loop
            clk <= '0';
            wait for clk_period/2;
            clk <= '1';
            wait for clk_period/2;
        end loop;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if pulse_count_clear = '1' then
                pulse_count <= 0;
            elsif btn_out = '1' then
                pulse_count <= pulse_count + 1;
            end if;
        end if;
    end process;

    dut: entity work.debounce_explicit
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ_c,
            DEBOUNCE_MS => DEBOUNCE_MS_c
        )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            btn_in    => btn_in,
            btn_out   => btn_out,
            btn_level => btn_level
        );

    test_runner: process
    begin
        test_runner_setup(runner, runner_cfg);

        if run("press_and_release_no_bounce") then
            rst_n <= '0';
            btn_in <= '1';
            pulse_count_clear <= '1';
            tick(1);
            pulse_count_clear <= '0';
            tick(5);
            rst_n <= '1';
            tick(5);
            btn_in <= '0';
            tick(DEBOUNCE_CYCLES_c + 10);
            assert btn_level = '0';
            tick(10);
            btn_in <= '1';
            tick(DEBOUNCE_CYCLES_c + 10);
            assert btn_level = '1';
            assert pulse_count = 1;
        end if;

        if run("quick_press_no_pulse") then
            rst_n <= '0';
            tick(2);
            rst_n <= '1';
            btn_in <= '1';
            tick(5);
            pulse_count_clear <= '1';
            tick(1);
            pulse_count_clear <= '0';
            btn_in <= '0';
            tick(DEBOUNCE_CYCLES_c/2);
            btn_in <= '1';
            tick(DEBOUNCE_CYCLES_c + 10);
            assert btn_level = '1';
            assert pulse_count = 0;
        end if;

        if run("bounce_then_press") then
            rst_n <= '0';
            tick(2);
            rst_n <= '1';
            btn_in <= '1';
            tick(5);
            pulse_count_clear <= '1';
            tick(1);
            pulse_count_clear <= '0';
            for j in 1 to 5 loop
                btn_in <= '0';
                tick(10);
                btn_in <= '1';
                tick(10);
            end loop;
            btn_in <= '0';
            tick(DEBOUNCE_CYCLES_c + 10);
            assert btn_level = '0';
            assert pulse_count = 1;
        end if;

        test_runner_cleanup(runner);
        wait;
    end process;
end architecture;
