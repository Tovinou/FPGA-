-- =============================================================================
-- tb_asyn_fifo.vhd
-- VUnit testbench for asyn_fifo.vhd only
--
-- Uses two independent clocks to exercise true CDC behaviour.
--
-- Tests:
--   tc_reset_empty     : FIFO empty after reset, not full
--   tc_write_read_same : write then read single word, data intact
--   tc_full_flag       : full asserts after writing 2^N entries
--   tc_no_write_full   : write ignored when full
--   tc_empty_flag      : empty asserts after draining all entries
--   tc_no_read_empty   : read pointer does not advance when empty
--   tc_sequential_data : write N words, read back in order
--   tc_cdc_25_165      : write at 25MHz, read at 165MHz (slow->fast)
--   tc_cdc_165_25      : write at 165MHz, read at 25MHz (fast->slow)
--   tc_fill_drain      : fill completely, drain completely, repeat
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_asyn_fifo is
    generic (runner_cfg : string);
end entity;

architecture sim of tb_asyn_fifo is

    -- Two independent clocks
    constant T_SLOW : time := 40 ns;      -- 25 MHz  (write side in most tests)
    constant T_FAST : time := 6061 ps;    -- 165 MHz (read side in most tests)

    signal wr_clk   : std_logic := '0';
    signal rd_clk   : std_logic := '0';
    signal wr_rst_n : std_logic := '0';
    signal rd_rst_n : std_logic := '0';

    -- Use small FIFO for fast simulation (depth = 2^4 = 16 entries)
    constant DEPTH_LOG2 : integer := 4;
    constant DEPTH      : integer := 2**DEPTH_LOG2;  -- 16

    signal wr_en    : std_logic := '0';
    signal wr_data  : std_logic_vector(15 downto 0) := (others => '0');
    signal wr_full  : std_logic;

    signal rd_en    : std_logic := '0';
    signal rd_data  : std_logic_vector(15 downto 0);
    signal rd_empty : std_logic;

    signal wr2_rst_n : std_logic := '0';
    signal rd2_rst_n : std_logic := '0';

    signal wr2_en    : std_logic := '0';
    signal wr2_data  : std_logic_vector(15 downto 0) := (others => '0');
    signal wr2_full  : std_logic;

    signal rd2_en    : std_logic := '0';
    signal rd2_data  : std_logic_vector(15 downto 0);
    signal rd2_empty : std_logic;

    -- Clock helpers
    procedure wr_wait(n : natural) is
    begin
        for i in 1 to n loop wait until rising_edge(wr_clk); end loop;
    end procedure;

    procedure rd_wait(n : natural) is
    begin
        for i in 1 to n loop wait until rising_edge(rd_clk); end loop;
    end procedure;

    procedure do_reset(
        signal wr_rst_n_out : out std_logic;
        signal rd_rst_n_out : out std_logic
    ) is
    begin
        wr_rst_n_out <= '0'; rd_rst_n_out <= '0';
        wr_wait(4); rd_wait(4);
        wr_rst_n_out <= '1'; rd_rst_n_out <= '1';
        wr_wait(4); rd_wait(4);
    end procedure;

    -- Write one word synchronously
    procedure write_word(
        signal wr_data_out : out std_logic_vector(15 downto 0);
        signal wr_en_out   : out std_logic;
        data               : std_logic_vector(15 downto 0)
    ) is
    begin
        wr_data_out <= data;
        wr_en_out   <= '1';
        wait until rising_edge(wr_clk);
        wr_en_out   <= '0';
    end procedure;

    -- Read one word, return data
    procedure read_word(
        signal rd_en_out   : out std_logic;
        signal rd_data_in  : in  std_logic_vector(15 downto 0);
        variable data_out  : out std_logic_vector(15 downto 0)
    ) is
    begin
        rd_en_out <= '1';
        wait until rising_edge(rd_clk);
        rd_en_out <= '0';
        wait until rising_edge(rd_clk);
        wait for 0 ns;
        data_out := rd_data_in;
    end procedure;

begin

    -- Independent free-running clocks
    wr_clk <= not wr_clk after T_SLOW / 2;
    rd_clk <= not rd_clk after T_FAST / 2;

    u_dut : entity work.asyn_fifo
        generic map (
            DATA_WIDTH => 16,
            DEPTH_LOG2 => DEPTH_LOG2
        )
        port map (
            wr_clk   => wr_clk,
            wr_rst_n => wr_rst_n,
            wr_en    => wr_en,
            wr_data  => wr_data,
            wr_full  => wr_full,
            rd_clk   => rd_clk,
            rd_rst_n => rd_rst_n,
            rd_en    => rd_en,
            rd_data  => rd_data,
            rd_empty => rd_empty
        );

    u_dut_fast_to_slow : entity work.asyn_fifo
        generic map (
            DATA_WIDTH => 16,
            DEPTH_LOG2 => DEPTH_LOG2
        )
        port map (
            wr_clk   => rd_clk,
            wr_rst_n => wr2_rst_n,
            wr_en    => wr2_en,
            wr_data  => wr2_data,
            wr_full  => wr2_full,
            rd_clk   => wr_clk,
            rd_rst_n => rd2_rst_n,
            rd_en    => rd2_en,
            rd_data  => rd2_data,
            rd_empty => rd2_empty
        );

    main : process
        variable got  : std_logic_vector(15 downto 0);
        variable tmp  : std_logic_vector(15 downto 0);
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            -- -----------------------------------------------------------------
            if run("tc_reset_empty") then
                info("After reset: empty=1, full=0");
                do_reset(wr_rst_n, rd_rst_n);
                -- Allow gray-code sync (2 cycles each domain)
                wr_wait(4); rd_wait(4);
                check_equal(rd_empty, std_logic'('1'), "empty after reset");
                check_equal(wr_full,  std_logic'('0'), "not full after reset");

            -- -----------------------------------------------------------------
            elsif run("tc_write_read_same") then
                info("Write one word, read it back");
                do_reset(wr_rst_n, rd_rst_n);
                write_word(wr_data, wr_en, x"ABCD");
                -- Allow CDC sync (2 wr + 2 rd clocks)
                wr_wait(4); rd_wait(6);
                check_equal(rd_empty, std_logic'('0'), "not empty after write");
                read_word(rd_en, rd_data, tmp);
                rd_wait(2);
                check_equal(tmp, std_logic_vector'(x"ABCD"), "read data = written data");
                rd_wait(4);
                check_equal(rd_empty, std_logic'('1'), "empty after reading last word");

            -- -----------------------------------------------------------------
            elsif run("tc_full_flag") then
                info("Full flag asserts after writing DEPTH entries");
                do_reset(wr_rst_n, rd_rst_n);
                -- Write exactly DEPTH words
                for i in 0 to DEPTH-1 loop
                    write_word(wr_data, wr_en, std_logic_vector(to_unsigned(i, 16)));
                end loop;
                -- Allow sync propagation
                wr_wait(6);
                check_equal(wr_full, std_logic'('1'), "full after writing " &
                            integer'image(DEPTH) & " entries");

            -- -----------------------------------------------------------------
            elsif run("tc_no_write_full") then
                info("Write rejected when FIFO full");
                do_reset(wr_rst_n, rd_rst_n);
                -- Fill completely
                for i in 0 to DEPTH-1 loop
                    write_word(wr_data, wr_en, std_logic_vector(to_unsigned(i, 16)));
                end loop;
                wr_wait(6);
                check_equal(wr_full, std_logic'('1'), "full before overflow attempt");
                -- Try to write one more — should be ignored
                write_word(wr_data, wr_en, x"DEAD");
                wr_wait(2);
                -- Read out all entries and verify last is not 0xDEAD
                for i in 0 to DEPTH-1 loop
                    read_word(rd_en, rd_data, tmp);
                    rd_wait(2);
                    check(tmp /= x"DEAD",
                          "overflow word must not appear in FIFO at position " &
                          integer'image(i));
                end loop;

            -- -----------------------------------------------------------------
            elsif run("tc_empty_flag") then
                info("Empty flag asserts after draining all entries");
                do_reset(wr_rst_n, rd_rst_n);
                write_word(wr_data, wr_en, x"1234");
                write_word(wr_data, wr_en, x"5678");
                rd_wait(8);
                read_word(rd_en, rd_data, tmp); rd_wait(4);
                read_word(rd_en, rd_data, tmp); rd_wait(4);
                check_equal(rd_empty, std_logic'('1'), "empty after draining all words");

            -- -----------------------------------------------------------------
            elsif run("tc_no_read_empty") then
                info("Read pointer does not advance when empty");
                do_reset(wr_rst_n, rd_rst_n);
                rd_wait(4);
                -- Attempt read on empty FIFO
                rd_en <= '1';
                rd_wait(4);
                rd_en <= '0';
                rd_wait(4);
                -- Now write one word and read it — if pointer advanced,
                -- we would read stale data
                write_word(wr_data, wr_en, x"CAFE");
                rd_wait(8);
                rd_wait(2);
                read_word(rd_en, rd_data, tmp);
                rd_wait(2);
                check_equal(tmp, std_logic_vector'(x"CAFE"),
                            "Correct data after spurious empty read");

            -- -----------------------------------------------------------------
            elsif run("tc_sequential_data") then
                info("Write N words, read back in exact order");
                do_reset(wr_rst_n, rd_rst_n);
                -- Write 8 words with distinct values
                for i in 0 to 7 loop
                    write_word(wr_data, wr_en,
                               std_logic_vector(to_unsigned(16#A000# + i, 16)));
                end loop;
                wr_wait(4); rd_wait(8);
                -- Read back and check order
                for i in 0 to 7 loop
                    check_equal(rd_empty, std_logic'('0'),
                                "not empty before read " & integer'image(i));
                    read_word(rd_en, rd_data, tmp);
                    rd_wait(2);
                    check_equal(tmp, std_logic_vector(to_unsigned(16#A000# + i, 16)),
                        "word " & integer'image(i) & " in order");
                end loop;
                rd_wait(4);
                check_equal(rd_empty, std_logic'('1'), "empty after reading all 8");

            -- -----------------------------------------------------------------
            elsif run("tc_cdc_slow_to_fast") then
                info("Write at slow clock (25MHz), read at fast clock (165MHz)");
                do_reset(wr_rst_n, rd_rst_n);
                -- Write 4 words slowly
                for i in 0 to 3 loop
                    write_word(wr_data, wr_en,
                               std_logic_vector(to_unsigned(16#B000# + i, 16)));
                end loop;
                -- Read at fast clock speed
                rd_wait(20);  -- allow CDC sync
                for i in 0 to 3 loop
                    check_equal(rd_empty, std_logic'('0'), "not empty slow->fast read " &
                                integer'image(i));
                    read_word(rd_en, rd_data, tmp);
                    rd_wait(3);
                    check_equal(tmp, std_logic_vector(to_unsigned(16#B000# + i, 16)),
                        "CDC slow->fast word " & integer'image(i));
                end loop;

            -- -----------------------------------------------------------------
            elsif run("tc_cdc_fast_to_slow") then
                info("Write at fast clock (165MHz), read at slow clock (25MHz)");
                do_reset(rd2_rst_n, wr2_rst_n);
                -- Write 4 words at fast clock rate (wr_clk of this instance = rd_clk)
                for i in 0 to 3 loop
                    wr2_data <= std_logic_vector(to_unsigned(16#C000# + i, 16));
                    wr2_en   <= '1';
                    wait until rising_edge(rd_clk);
                    wr2_en <= '0';
                    wait until rising_edge(rd_clk);
                end loop;

                -- Allow CDC into slow domain (rd_clk of this instance = wr_clk)
                wr_wait(8);

                for i in 0 to 3 loop
                    check_equal(rd2_empty, std_logic'('0'),
                                "not empty fast->slow read " & integer'image(i));
                    rd2_en <= '1';
                    wait until rising_edge(wr_clk);
                    wait for 0 ns;
                    tmp := rd2_data;
                    rd2_en <= '0';
                    wr_wait(2);
                    check_equal(tmp, std_logic_vector(to_unsigned(16#C000# + i, 16)),
                                "CDC fast->slow word " & integer'image(i));
                end loop;

            -- -----------------------------------------------------------------
            elsif run("tc_fill_drain") then
                info("Fill completely, drain completely, repeat x3");
                do_reset(wr_rst_n, rd_rst_n);
                for pass in 1 to 3 loop
                    -- Fill
                    for i in 0 to DEPTH-1 loop
                        write_word(wr_data, wr_en, std_logic_vector(to_unsigned(i, 16)));
                    end loop;
                    wr_wait(6);
                    check_equal(wr_full, std_logic'('1'),
                        "full on pass " & integer'image(pass));
                    -- Drain
                    for i in 0 to DEPTH-1 loop
                        rd_en <= '1';
                        wait until rising_edge(rd_clk);
                        rd_en <= '0';
                        rd_wait(2);
                    end loop;
                    rd_wait(6);
                    check_equal(rd_empty, std_logic'('1'),
                        "empty after drain on pass " & integer'image(pass));
                end loop;

            end if;
        end loop;

        test_runner_cleanup(runner);
    end process;

    test_runner_watchdog(runner, 10 ms);

end architecture sim;
