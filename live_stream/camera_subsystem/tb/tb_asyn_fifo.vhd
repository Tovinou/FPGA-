-- =============================================================================
-- tb_asyn_fifo.vhd
-- VUnit testbench for asyn_fifo.vhd
--
-- Tests the FIFO in ALL three clock-pair configurations used by the project:
--
--   Suite A — Functional (clock-pair agnostic, small depth=16):
--     tc_reset_empty        : empty=1, full=0 after reset
--     tc_write_read_single  : single word write/read data integrity
--     tc_full_flag          : full asserts at exactly DEPTH writes
--     tc_no_write_when_full : write silently rejected when full
--     tc_empty_flag         : empty asserts after last word drained
--     tc_no_read_when_empty : rd_ptr does not advance on empty FIFO
--     tc_sequential_data    : N words read back in FIFO order
--     tc_fill_drain_repeat  : fill/drain cycle x3 — no state corruption
--
--   Suite B — Camera CDC: 24 MHz PCLK write -> 165 MHz read
--     tc_cam_cdc_single     : one RGB565 pixel survives CDC
--     tc_cam_cdc_burst      : 16-pixel burst arrives in order
--     tc_cam_cdc_full_flag  : full propagates from 24MHz write back
--     tc_cam_cdc_empty_flag : empty propagates in 165MHz read domain
--     tc_cam_cdc_no_loss    : write count == read count
--
--   Suite C — VGA CDC: 165 MHz write -> 25 MHz read
--     tc_vga_cdc_single     : one pixel 165->25MHz intact
--     tc_vga_cdc_burst      : burst write drained in order at 25MHz
--     tc_vga_cdc_backpressure: full deasserts after partial drain
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

    constant T_24M  : time := 41667 ps;
    constant T_25M  : time := 40 ns;
    constant T_165M : time := 6061 ps;

    constant DEPTH_LOG2 : integer := 4;
    constant DEPTH      : integer := 2**DEPTH_LOG2;  -- 16

    signal wr_clk   : std_logic := '0';
    signal rd_clk   : std_logic := '0';
    signal wr_rst_n : std_logic := '0';
    signal rd_rst_n : std_logic := '0';
    signal wr_en    : std_logic := '0';
    signal wr_data  : std_logic_vector(15 downto 0) := (others => '0');
    signal wr_full  : std_logic;
    signal rd_en    : std_logic := '0';
    signal rd_data  : std_logic_vector(15 downto 0);
    signal rd_empty : std_logic;

    -- Clock period controls (set per suite)
    shared variable wr_period : time := T_24M;
    shared variable rd_period : time := T_165M;

    procedure wr_wait(n : natural) is
    begin
        for i in 1 to n loop wait until rising_edge(wr_clk); end loop;
    end procedure;

    procedure rd_wait(n : natural) is
    begin
        for i in 1 to n loop wait until rising_edge(rd_clk); end loop;
    end procedure;

    procedure do_reset is
    begin
        wr_rst_n <= '0'; rd_rst_n <= '0';
        wr_en <= '0'; rd_en <= '0';
        wr_wait(6); rd_wait(6);
        wr_rst_n <= '1'; rd_rst_n <= '1';
        wr_wait(6); rd_wait(6);
    end procedure;

    procedure write_word(data : std_logic_vector(15 downto 0)) is
    begin
        wait until rising_edge(wr_clk);
        wr_data <= data; wr_en <= '1';
        wait until rising_edge(wr_clk);
        wr_en <= '0';
    end procedure;

    procedure read_word(variable dout : out std_logic_vector(15 downto 0)) is
    begin
        wait until rising_edge(rd_clk);
        rd_en <= '1';
        wait until rising_edge(rd_clk);
        rd_en <= '0';
        rd_wait(2);
        dout := rd_data;
    end procedure;

    procedure write_burst(n : natural; base : natural) is
    begin
        for i in 0 to n-1 loop
            write_word(std_logic_vector(to_unsigned((base+i) mod 65536, 16)));
        end loop;
    end procedure;

    procedure drain_all(variable cnt : out natural) is
        variable c : natural := 0;
        variable t : std_logic_vector(15 downto 0);
    begin
        while rd_empty = '0' loop
            read_word(t); c := c+1;
            exit when c > 2048;
        end loop;
        cnt := c;
    end procedure;

begin

    -- Clock generators driven by shared variables
    p_wr_clk : process
    begin
        loop
            wr_clk <= '0'; wait for wr_period/2;
            wr_clk <= '1'; wait for wr_period/2;
        end loop;
    end process;

    p_rd_clk : process
    begin
        loop
            rd_clk <= '0'; wait for rd_period/2;
            rd_clk <= '1'; wait for rd_period/2;
        end loop;
    end process;

    u_dut : entity work.asyn_fifo
        generic map (DATA_WIDTH => 16, DEPTH_LOG2 => DEPTH_LOG2)
        port map (
            wr_clk => wr_clk, wr_rst_n => wr_rst_n,
            wr_en  => wr_en,  wr_data  => wr_data, wr_full => wr_full,
            rd_clk => rd_clk, rd_rst_n => rd_rst_n,
            rd_en  => rd_en,  rd_data  => rd_data, rd_empty => rd_empty
        );

    main : process
        variable tmp : std_logic_vector(15 downto 0);
        variable cnt : natural;
        variable ok  : boolean;
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            -- =================================================================
            -- SUITE A — Functional
            -- =================================================================
            if run("tc_reset_empty") then
                info("A: empty=1 full=0 after reset");
                wr_period := T_24M; rd_period := T_165M;
                do_reset;
                wr_wait(4); rd_wait(4);
                check_equal(rd_empty, '1', "empty after reset");
                check_equal(wr_full,  '0', "not full after reset");

            elsif run("tc_write_read_single") then
                info("A: write 0xABCD read it back");
                wr_period := T_24M; rd_period := T_165M;
                do_reset;
                write_word(x"ABCD");
                rd_wait(8);
                check_equal(rd_empty, '0', "not empty after write");
                read_word(tmp);
                check_equal(tmp, std_logic_vector'(x"ABCD"), "data intact");
                rd_wait(4);
                check_equal(rd_empty, '1', "empty after read");

            elsif run("tc_full_flag") then
                info("A: full asserts at exactly " & integer'image(DEPTH) & " entries");
                wr_period := T_24M; rd_period := T_165M;
                do_reset;
                write_burst(DEPTH, 0);
                wr_wait(8);
                check_equal(wr_full, '1', "full at DEPTH entries");

            elsif run("tc_no_write_when_full") then
                info("A: overflow write rejected");
                wr_period := T_24M; rd_period := T_165M;
                do_reset;
                write_burst(DEPTH, 0);
                wr_wait(8);
                write_word(x"BEEF");   -- overflow
                wr_wait(4);
                ok := true;
                for i in 0 to DEPTH-1 loop
                    read_word(tmp);
                    if tmp = x"BEEF" then ok := false; end if;
                end loop;
                check(ok, "overflow word 0xBEEF must not appear in FIFO");

            elsif run("tc_empty_flag") then
                info("A: empty asserts after draining all words");
                wr_period := T_24M; rd_period := T_165M;
                do_reset;
                write_word(x"1111"); write_word(x"2222");
                rd_wait(8);
                read_word(tmp); check_equal(tmp, std_logic_vector'(x"1111"), "w0");
                read_word(tmp); check_equal(tmp, std_logic_vector'(x"2222"), "w1");
                rd_wait(4);
                check_equal(rd_empty, '1', "empty after draining 2 words");

            elsif run("tc_no_read_when_empty") then
                info("A: rd_ptr does not advance on empty FIFO");
                wr_period := T_24M; rd_period := T_165M;
                do_reset;
                rd_en <= '1'; rd_wait(6); rd_en <= '0'; rd_wait(4);
                write_word(x"CAFE");
                rd_wait(10);
                read_word(tmp);
                check_equal(tmp, std_logic_vector'(x"CAFE"),
                    "correct data after spurious empty read");

            elsif run("tc_sequential_data") then
                info("A: 8 words read back in order");
                wr_period := T_24M; rd_period := T_165M;
                do_reset;
                write_burst(8, 16#A000#);
                wr_wait(4); rd_wait(10);
                for i in 0 to 7 loop
                    check_equal(rd_empty, '0', "not empty at word " & integer'image(i));
                    read_word(tmp);
                    check_equal(tmp,
                        std_logic_vector(to_unsigned(16#A000#+i, 16)),
                        "word " & integer'image(i) & " correct");
                end loop;
                rd_wait(4);
                check_equal(rd_empty, '1', "empty after 8 reads");

            elsif run("tc_fill_drain_repeat") then
                info("A: fill/drain x3 no corruption");
                wr_period := T_24M; rd_period := T_165M;
                do_reset;
                for pass in 1 to 3 loop
                    write_burst(DEPTH, pass*100);
                    wr_wait(8);
                    check_equal(wr_full, '1', "full pass " & integer'image(pass));
                    drain_all(cnt);
                    rd_wait(8);
                    check_equal(rd_empty, '1', "empty pass " & integer'image(pass));
                    check_equal(cnt, DEPTH, "count pass " & integer'image(pass));
                end loop;

            -- =================================================================
            -- SUITE B — Camera CDC: 24 MHz write -> 165 MHz read
            -- =================================================================
            elsif run("tc_cam_cdc_single") then
                info("B CAM: one RGB565 pixel 24MHz->165MHz");
                wr_period := T_24M; rd_period := T_165M;
                do_reset;
                write_word(x"F81F");
                rd_wait(10);
                check_equal(rd_empty, '0', "not empty after CDC");
                read_word(tmp);
                check_equal(tmp, std_logic_vector'(x"F81F"),
                    "24MHz->165MHz pixel intact");

            elsif run("tc_cam_cdc_burst") then
                info("B CAM: 16-pixel burst in order at 165MHz");
                wr_period := T_24M; rd_period := T_165M;
                do_reset;
                write_burst(16, 16#1000#);
                rd_wait(15);
                for i in 0 to 15 loop
                    check_equal(rd_empty, '0',
                        "not empty at pixel " & integer'image(i));
                    read_word(tmp);
                    check_equal(tmp,
                        std_logic_vector(to_unsigned(16#1000#+i, 16)),
                        "cam burst pixel " & integer'image(i));
                end loop;
                rd_wait(4);
                check_equal(rd_empty, '1', "empty after burst drain");

            elsif run("tc_cam_cdc_full_flag") then
                info("B CAM: full flag CDC 24MHz write domain");
                wr_period := T_24M; rd_period := T_165M;
                do_reset;
                write_burst(DEPTH, 0);
                wr_wait(10);
                check_equal(wr_full, '1', "full in 24MHz domain");
                rd_wait(6); read_word(tmp);
                wr_wait(10);
                check_equal(wr_full, '0',
                    "full deasserts after drain (165->24MHz CDC)");

            elsif run("tc_cam_cdc_empty_flag") then
                info("B CAM: empty flag in 165MHz read domain");
                wr_period := T_24M; rd_period := T_165M;
                do_reset;
                write_burst(4, 16#CC00#);
                rd_wait(12);
                drain_all(cnt);
                rd_wait(6);
                check_equal(rd_empty, '1', "empty after draining camera pixels");

            elsif run("tc_cam_cdc_no_loss") then
                info("B CAM: write count == read count (no pixel loss)");
                wr_period := T_24M; rd_period := T_165M;
                do_reset;
                write_burst(DEPTH-2, 0);
                rd_wait(15);
                drain_all(cnt);
                rd_wait(4);
                check_equal(cnt, DEPTH-2,
                    "all " & integer'image(DEPTH-2) & " pixels readable");

            -- =================================================================
            -- SUITE C — VGA CDC: 165 MHz write -> 25 MHz read
            -- =================================================================
            elsif run("tc_vga_cdc_single") then
                info("C VGA: one pixel 165MHz->25MHz");
                wr_period := T_165M; rd_period := T_25M;
                do_reset;
                write_word(x"07E0");
                wr_wait(10); rd_wait(5);
                check_equal(rd_empty, '0', "not empty after 165->25MHz CDC");
                read_word(tmp);
                check_equal(tmp, std_logic_vector'(x"07E0"),
                    "165MHz->25MHz pixel intact");

            elsif run("tc_vga_cdc_burst") then
                info("C VGA: burst at 165MHz drained in order at 25MHz");
                wr_period := T_165M; rd_period := T_25M;
                do_reset;
                write_burst(8, 16#D000#);
                wr_wait(6); rd_wait(8);
                for i in 0 to 7 loop
                    check_equal(rd_empty, '0',
                        "not empty at VGA pixel " & integer'image(i));
                    read_word(tmp);
                    check_equal(tmp,
                        std_logic_vector(to_unsigned(16#D000#+i, 16)),
                        "VGA pixel " & integer'image(i));
                end loop;
                rd_wait(6);
                check_equal(rd_empty, '1', "empty after VGA drain");

            elsif run("tc_vga_cdc_backpressure") then
                info("C VGA: full deasserts after partial 25MHz drain");
                wr_period := T_165M; rd_period := T_25M;
                do_reset;
                write_burst(DEPTH, 16#E000#);
                wr_wait(8);
                check_equal(wr_full, '1', "full after 165MHz fill");
                for i in 0 to DEPTH/2-1 loop read_word(tmp); end loop;
                wr_wait(10);
                check_equal(wr_full, '0',
                    "full deasserts after partial 25MHz drain");
                write_burst(DEPTH/2, 16#E100#);
                wr_wait(6);
                check_equal(wr_full, '0', "not full after writing to half-empty");

            end if;
        end loop;

        test_runner_cleanup(runner);
    end process;

    test_runner_watchdog(runner, 20 ms);

end architecture sim;
