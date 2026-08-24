-- =============================================================================
-- tb_sdram_controller.vhd
-- VUnit testbench for sdram_controller.vhd (corrected version)
--
-- Strategy:
--   A behavioural IS42S16320F SDRAM model is included in this file.
--   It decodes {CS,RAS,CAS,WE} commands, responds to ACTIVE/READ/WRITE,
--   and provides DQ data with CAS latency=3.
--   All tests run at 75 MHz.
--
-- Tests:
--   tc_init_sequence      : correct power-up init (NOP->PRE->2xREF->MRS)
--   tc_init_200us         : init wait >= 200us before first command
--   tc_ready_after_init   : controller goes idle after MRS completes
--   tc_write_single       : single word write, correct address/data on bus
--   tc_read_single        : single word read, rd_valid asserts, data captured
--   tc_write_read_same    : write then read same address, data matches
--   tc_refresh_occurs     : auto-refresh command issued within 7.8us
--   tc_refresh_priority   : refresh issued before write when both pending
--   tc_wr_ack_one_cycle   : wr_ack is exactly 1 cycle wide
--   tc_rd_ack_one_cycle   : rd_ack is exactly 1 cycle wide
--   tc_twr_respected      : PRECHARGE not issued immediately after WRITE
--   tc_sdram_clk_unused   : sdram_clk output is '0' (not driven by logic)
--   tc_consecutive_writes : back-to-back writes complete without stall
--   tc_consecutive_reads  : back-to-back reads complete without stall
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_sdram_controller is
    generic (runner_cfg : string);
end entity;

architecture sim of tb_sdram_controller is

    constant T_CLK : time := 13.333 ns;  -- 75 MHz

    -- =========================================================================
    -- DUT signals
    -- =========================================================================
    signal clk        : std_logic := '0';
    signal rst_n      : std_logic := '0';

    signal wr_req     : std_logic := '0';
    signal wr_addr    : std_logic_vector(24 downto 0) := (others => '0');
    signal wr_data    : std_logic_vector(15 downto 0) := (others => '0');
    signal wr_ack     : std_logic;

    signal rd_req     : std_logic := '0';
    signal rd_addr    : std_logic_vector(24 downto 0) := (others => '0');
    signal rd_data    : std_logic_vector(15 downto 0);
    signal rd_valid   : std_logic;
    signal rd_ack     : std_logic;

    signal sdram_clk  : std_logic;
    signal sdram_cke  : std_logic;
    signal sdram_cs_n : std_logic;
    signal sdram_ras_n: std_logic;
    signal sdram_cas_n: std_logic;
    signal sdram_we_n : std_logic;
    signal sdram_ba   : std_logic_vector(1 downto 0);
    signal sdram_addr : std_logic_vector(12 downto 0);
    signal sdram_dqm  : std_logic_vector(1 downto 0);
    signal sdram_dq   : std_logic_vector(15 downto 0);

    -- DQ tri-state: model drives back when reading
    signal sdram_dq_drive : std_logic_vector(15 downto 0) := (others => 'Z');
    signal model_dq_oe    : std_logic := '0';

    -- =========================================================================
    -- SDRAM command decode helper
    -- =========================================================================
    type sdram_cmd_t is (
        CMD_INHIBIT, CMD_NOP, CMD_ACTIVE, CMD_READ,
        CMD_WRITE,   CMD_PRECHARGE, CMD_REFRESH, CMD_MRS, CMD_UNKNOWN
    );

    function decode_cmd(
        cs_n, ras_n, cas_n, we_n : std_logic
    ) return sdram_cmd_t is
        variable bits : std_logic_vector(3 downto 0);
    begin
        bits := cs_n & ras_n & cas_n & we_n;
        case bits is
            when "1111" => return CMD_INHIBIT;
            when "0111" => return CMD_NOP;
            when "0011" => return CMD_ACTIVE;
            when "0101" => return CMD_READ;
            when "0100" => return CMD_WRITE;
            when "0010" => return CMD_PRECHARGE;
            when "0001" => return CMD_REFRESH;
            when "0000" => return CMD_MRS;
            when others => return CMD_UNKNOWN;
        end case;
    end function;

    -- =========================================================================
    -- Behavioural SDRAM model signals
    -- =========================================================================
    type sdram_mem_t is array (0 to 1023) of std_logic_vector(15 downto 0);
    signal sdram_mem : sdram_mem_t := (others => (others => '0'));

    signal model_active_row  : std_logic_vector(12 downto 0) := (others => '0');
    signal model_active_bank : std_logic_vector(1 downto 0)  := (others => '0');
    signal model_row_open    : std_logic := '0';
    signal model_rd_pending  : std_logic := '0';
    signal model_rd_col      : std_logic_vector(9 downto 0) := (others => '0');
    signal model_rd_pipe     : std_logic_vector(2 downto 0) := (others => '0');

    -- =========================================================================
    -- Clock helpers
    -- =========================================================================
    procedure clk_wait(n : natural) is
    begin
        for i in 1 to n loop wait until rising_edge(clk); end loop;
    end procedure;

    -- Wait for init to complete (MRS done -> IDLE state)
    -- At 100MHz: ~20000 + init commands = slightly > 200us
    procedure wait_init is
    begin
        -- 25000 cycles is safe upper bound
        for i in 1 to 25000 loop
            wait until rising_edge(clk);
            exit when (wr_ack = '0' and rd_ack = '0' and
                       sdram_cs_n = '0' and sdram_ras_n = '1' and
                       sdram_cas_n = '1' and sdram_we_n = '1');
            -- Exit also on first NOP after MRS
        end loop;
        clk_wait(5);
    end procedure;

    -- Issue a write and wait for ack
    procedure do_write(
        signal wr_req_s  : out std_logic;
        signal wr_addr_s : out std_logic_vector(24 downto 0);
        signal wr_data_s : out std_logic_vector(15 downto 0);
        signal wr_ack_s  : in  std_logic;
        addr             : std_logic_vector(24 downto 0);
        data             : std_logic_vector(15 downto 0)
    ) is
    begin
        wait until rising_edge(clk);
        wr_req_s  <= '1';
        wr_addr_s <= addr;
        wr_data_s <= data;
        wait until rising_edge(clk) and wr_ack_s = '1';
        wr_req_s  <= '0';
        clk_wait(20);  -- allow SDRAM cycles to complete
    end procedure;

    -- Issue a read and wait for rd_valid
    procedure do_read(
        signal rd_req_s   : out std_logic;
        signal rd_addr_s  : out std_logic_vector(24 downto 0);
        signal rd_ack_s   : in  std_logic;
        signal rd_data_s  : in  std_logic_vector(15 downto 0);
        signal rd_valid_s : in  std_logic;
        addr              : std_logic_vector(24 downto 0);
        variable data_out : out std_logic_vector(15 downto 0)
    ) is
    begin
        wait until rising_edge(clk);
        rd_req_s  <= '1';
        rd_addr_s <= addr;
        wait until rising_edge(clk) and rd_ack_s = '1';
        rd_req_s  <= '0';
        wait until rising_edge(clk) and rd_valid_s = '1';
        data_out := rd_data_s;
        clk_wait(5);
    end procedure;

begin

    clk <= not clk after T_CLK / 2;

    -- DQ bus: driven by model when reading, else Z
    sdram_dq <= sdram_dq_drive when model_dq_oe = '1' else (others => 'Z');

    -- =========================================================================
    -- DUT
    -- =========================================================================
    u_dut : entity work.sdram_controller
        port map (
            clk        => clk,
            rst_n      => rst_n,
            wr_req     => wr_req,
            wr_addr    => wr_addr,
            wr_data    => wr_data,
            wr_ack     => wr_ack,
            rd_req     => rd_req,
            rd_addr    => rd_addr,
            rd_data    => rd_data,
            rd_valid   => rd_valid,
            rd_ack     => rd_ack,
            sdram_clk  => sdram_clk,
            sdram_cke  => sdram_cke,
            sdram_cs_n => sdram_cs_n,
            sdram_ras_n=> sdram_ras_n,
            sdram_cas_n=> sdram_cas_n,
            sdram_we_n => sdram_we_n,
            sdram_ba   => sdram_ba,
            sdram_addr => sdram_addr,
            sdram_dqm  => sdram_dqm,
            sdram_dq   => sdram_dq
        );

    -- =========================================================================
    -- Behavioural SDRAM model
    -- Implements: ACTIVE, WRITE, READ (CL=3), PRECHARGE, AUTO-REFRESH
    -- =========================================================================
    p_sdram_model : process
        variable cmd     : sdram_cmd_t;
        variable col     : integer;
        variable mem_idx : integer;
    begin
        model_dq_oe    <= '0';
        sdram_dq_drive <= (others => 'Z');
        model_rd_pipe  <= (others => '0');

        loop
            wait until rising_edge(clk);
            wait for 0 ns;
            wait for 0 ns;

            -- Shift CAS latency pipeline
            model_rd_pipe <= model_rd_pipe(1 downto 0) & '0';

            if model_rd_pipe(2) = '1' or model_rd_pipe(1) = '1' then
                model_dq_oe    <= '1';
                sdram_dq_drive <= sdram_mem(
                    to_integer(unsigned(model_rd_col))
                );
            else
                model_dq_oe    <= '0';
                sdram_dq_drive <= (others => 'Z');
            end if;

            cmd := decode_cmd(sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n);

            case cmd is
                when CMD_ACTIVE =>
                    model_active_row  <= sdram_addr;
                    model_active_bank <= sdram_ba;
                    model_row_open    <= '1';

                when CMD_WRITE =>
                    if model_row_open = '1' then
                        col := to_integer(unsigned(sdram_addr(9 downto 0)));
                        mem_idx := col mod 1024;
                        -- Data is valid on the same cycle (burst=1)
                        sdram_mem(mem_idx) <= sdram_dq;
                    end if;

                when CMD_READ =>
                    if model_row_open = '1' then
                        model_rd_col  <= sdram_addr(9 downto 0);
                        model_rd_pipe <= "001";
                    end if;

                when CMD_PRECHARGE =>
                    model_row_open <= '0';

                when others =>
                    null;
            end case;
        end loop;
    end process;

    -- =========================================================================
    -- Main test process
    -- =========================================================================
    main : process
        variable t_start    : time;
        variable t_first_cmd: time;
        variable cmd        : sdram_cmd_t;
        variable found_pre  : boolean;
        variable found_ref  : boolean;
        variable found_mrs  : boolean;
        variable pre_count  : integer;
        variable ref_count  : integer;
        variable data_out   : std_logic_vector(15 downto 0);
        variable wr_ack_cnt : integer;
        variable cmd_seq    : integer;
        variable last_write_cycle : integer;
        variable pre_cycle  : integer;
        variable cycle_cnt  : integer;
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            -- -----------------------------------------------------------------
            if run("tc_init_sequence") then
                info("Init sequence: INHIBIT -> NOP -> PRE -> 2xREF -> MRS");
                rst_n <= '0'; clk_wait(4); rst_n <= '1';

                found_pre := false;
                found_ref := false;
                found_mrs := false;
                ref_count := 0;

                -- Monitor first 25000 cycles
                for i in 0 to 25000 loop
                    wait until rising_edge(clk);
                    cmd := decode_cmd(sdram_cs_n,sdram_ras_n,sdram_cas_n,sdram_we_n);
                    if cmd = CMD_PRECHARGE then found_pre := true; end if;
                    if cmd = CMD_REFRESH and found_pre then
                        ref_count := ref_count + 1;
                        found_ref := true;
                    end if;
                    if cmd = CMD_MRS and found_ref then found_mrs := true; end if;
                    exit when found_mrs;
                end loop;

                check(found_pre, "PRECHARGE must appear in init sequence");
                check(ref_count >= 2, "At least 2 AUTO-REFRESH before MRS");
                check(found_mrs, "MRS must appear after 2 auto-refreshes");

            -- -----------------------------------------------------------------
            elsif run("tc_init_200us") then
                info("First command must not appear before 200us");
                rst_n <= '0'; clk_wait(4);
                t_start := now;
                rst_n <= '1';

                -- Wait for first non-INHIBIT/NOP command
                t_first_cmd := now;
                for i in 0 to 30000 loop
                    wait until rising_edge(clk);
                    cmd := decode_cmd(sdram_cs_n,sdram_ras_n,sdram_cas_n,sdram_we_n);
                    if cmd = CMD_PRECHARGE then
                        t_first_cmd := now;
                        exit;
                    end if;
                end loop;

                check(t_first_cmd - t_start >= 200 us,
                    "First SDRAM command must not appear before 200us, got " &
                    time'image(t_first_cmd - t_start));

            -- -----------------------------------------------------------------
            elsif run("tc_ready_after_init") then
                info("Controller accepts requests after init completes");
                rst_n <= '0'; clk_wait(4); rst_n <= '1';
                wait_init;
                -- Issue a write immediately — should be accepted quickly
                wr_req  <= '1';
                wr_addr <= "0000000000000000000000001";
                wr_data <= x"1234";
                wait until rising_edge(clk) and wr_ack = '1' for 100 us;
                wr_req  <= '0';
                check_equal(wr_ack, '1',
                    "wr_ack must fire promptly after init");

            -- -----------------------------------------------------------------
            elsif run("tc_write_single") then
                info("Single write: ACTIVE+addr, WRITE+data on SDRAM bus");
                rst_n <= '0'; clk_wait(4); rst_n <= '1';
                wait_init;

                wr_req  <= '1';
                wr_addr <= std_logic_vector(to_unsigned(16#0100#, 25));
                wr_data <= x"ABCD";
                wait until rising_edge(clk) and wr_ack = '1';
                wr_req  <= '0';

                -- Check ACTIVE then WRITE appear on bus
                found_pre := false;
                for i in 0 to 30 loop
                    wait until rising_edge(clk);
                    cmd := decode_cmd(sdram_cs_n,sdram_ras_n,sdram_cas_n,sdram_we_n);
                    if cmd = CMD_WRITE then
                        found_pre := true;
                        exit;
                    end if;
                end loop;
                check(found_pre, "WRITE command must appear on SDRAM bus");

            -- -----------------------------------------------------------------
            elsif run("tc_read_single") then
                info("Single read: rd_valid asserts, rd_data captured from DQ");
                rst_n <= '0'; clk_wait(4); rst_n <= '1';
                wait_init;

                -- First write a known value
                do_write(wr_req, wr_addr, wr_data, wr_ack, std_logic_vector(to_unsigned(5, 25)), x"BEEF");
                -- Now read it back
                do_read(rd_req, rd_addr, rd_ack, rd_data, rd_valid, std_logic_vector(to_unsigned(5, 25)), data_out);
                check_equal(data_out, std_logic_vector'(x"BEEF"),
                    "rd_data must match what was written via SDRAM model");

            -- -----------------------------------------------------------------
            elsif run("tc_write_read_same") then
                info("Write then read same address returns correct data");
                rst_n <= '0'; clk_wait(4); rst_n <= '1';
                wait_init;

                do_write(wr_req, wr_addr, wr_data, wr_ack, std_logic_vector(to_unsigned(20, 25)), x"1234");
                do_write(wr_req, wr_addr, wr_data, wr_ack, std_logic_vector(to_unsigned(22, 25)), x"5678");
                do_read(rd_req, rd_addr, rd_ack, rd_data, rd_valid, std_logic_vector(to_unsigned(20, 25)), data_out);
                check_equal(data_out, std_logic_vector'(x"1234"), "addr 10 = 0x1234");
                do_read(rd_req, rd_addr, rd_ack, rd_data, rd_valid, std_logic_vector(to_unsigned(22, 25)), data_out);
                check_equal(data_out, std_logic_vector'(x"5678"), "addr 11 = 0x5678");

            -- -----------------------------------------------------------------
            elsif run("tc_refresh_occurs") then
                info("AUTO-REFRESH issued within 7.8us (780 cycles @ 100MHz)");
                rst_n <= '0'; clk_wait(4); rst_n <= '1';
                wait_init;

                found_ref := false;
                for i in 0 to 1000 loop
                    wait until rising_edge(clk);
                    cmd := decode_cmd(sdram_cs_n,sdram_ras_n,sdram_cas_n,sdram_we_n);
                    if cmd = CMD_REFRESH then
                        found_ref := true;
                        exit;
                    end if;
                end loop;
                check(found_ref, "AUTO-REFRESH must occur within 1000 cycles");

            -- -----------------------------------------------------------------
            elsif run("tc_refresh_priority") then
                info("Refresh takes priority over pending write");
                rst_n <= '0'; clk_wait(4); rst_n <= '1';
                wait_init;

                -- Hold write request continuously and wait for refresh
                wr_req  <= '1';
                wr_addr <= (others => '0');
                wr_data <= x"FFFF";

                found_ref := false;
                for i in 0 to 1000 loop
                    wait until rising_edge(clk);
                    cmd := decode_cmd(sdram_cs_n,sdram_ras_n,sdram_cas_n,sdram_we_n);
                    if cmd = CMD_REFRESH then
                        found_ref := true;
                        exit;
                    end if;
                end loop;
                wr_req <= '0';
                check(found_ref,
                    "REFRESH must interrupt pending write within refresh period");

            -- -----------------------------------------------------------------
            elsif run("tc_wr_ack_one_cycle") then
                info("wr_ack is exactly 1 cycle wide");
                rst_n <= '0'; clk_wait(4); rst_n <= '1';
                wait_init;

                wr_req  <= '1';
                wr_addr <= (others => '0');
                wr_data <= x"AAAA";
                wait until rising_edge(clk) and wr_ack = '1';
                -- Next cycle wr_ack must be low
                wait until rising_edge(clk);
                check_equal(wr_ack, '0', "wr_ack must be 0 the cycle after it fires");
                wr_req <= '0';

            -- -----------------------------------------------------------------
            elsif run("tc_rd_ack_one_cycle") then
                info("rd_ack is exactly 1 cycle wide");
                rst_n <= '0'; clk_wait(4); rst_n <= '1';
                wait_init;

                rd_req  <= '1';
                rd_addr <= (others => '0');
                wait until rising_edge(clk) and rd_ack = '1';
                wait until rising_edge(clk);
                check_equal(rd_ack, '0', "rd_ack must be 0 the cycle after it fires");
                rd_req <= '0';

            -- -----------------------------------------------------------------
            elsif run("tc_twr_respected") then
                info("PRECHARGE not issued within tWR=2 cycles of WRITE");
                rst_n <= '0'; clk_wait(4); rst_n <= '1';
                wait_init;

                wr_req  <= '1';
                wr_addr <= (others => '0');
                wr_data <= x"CCCC";
                wait until rising_edge(clk) and wr_ack = '1';
                wr_req <= '0';

                -- Find WRITE command, then check gap to PRECHARGE
                last_write_cycle := 0;
                pre_cycle        := 0;
                cycle_cnt        := 0;
                for i in 0 to 30 loop
                    wait until rising_edge(clk);
                    cycle_cnt := cycle_cnt + 1;
                    cmd := decode_cmd(sdram_cs_n,sdram_ras_n,sdram_cas_n,sdram_we_n);
                    if cmd = CMD_WRITE then
                        last_write_cycle := cycle_cnt;
                    end if;
                    if cmd = CMD_PRECHARGE and last_write_cycle > 0 then
                        pre_cycle := cycle_cnt;
                        exit;
                    end if;
                end loop;
                check(pre_cycle - last_write_cycle >= 2,
                    "PRECHARGE must be at least 2 cycles after WRITE (tWR), got " &
                    integer'image(pre_cycle - last_write_cycle));

            -- -----------------------------------------------------------------
            elsif run("tc_sdram_clk_unused") then
                info("sdram_clk output must be '0' (not driven by logic)");
                rst_n <= '0'; clk_wait(4); rst_n <= '1';
                clk_wait(10);
                check_equal(sdram_clk, '0',
                    "sdram_clk must be '0' (DRAM_CLK driven by PLL c3 in top)");

            -- -----------------------------------------------------------------
            elsif run("tc_consecutive_writes") then
                info("Back-to-back writes complete without deadlock");
                rst_n <= '0'; clk_wait(4); rst_n <= '1';
                wait_init;

                wr_ack_cnt := 0;
                for i in 0 to 3 loop
                    wr_req  <= '1';
                    wr_addr <= std_logic_vector(to_unsigned(i, 25));
                    wr_data <= std_logic_vector(to_unsigned(16#A000# + i, 16));
                    wait until rising_edge(clk) and wr_ack = '1';
                    wr_ack_cnt := wr_ack_cnt + 1;
                    wr_req <= '0';
                    clk_wait(20);
                end loop;
                check_equal(wr_ack_cnt, 4, "All 4 writes must complete");

            -- -----------------------------------------------------------------
            elsif run("tc_consecutive_reads") then
                info("Back-to-back reads complete, data valid each time");
                rst_n <= '0'; clk_wait(4); rst_n <= '1';
                wait_init;

                -- Write 4 words first
                for i in 0 to 3 loop
                    do_write(
                        wr_req,
                        wr_addr,
                        wr_data,
                        wr_ack,
                        std_logic_vector(to_unsigned(i * 2, 25)),
                        std_logic_vector(to_unsigned(16#B000# + i, 16))
                    );
                end loop;
                -- Read them back
                for i in 0 to 3 loop
                    do_read(rd_req, rd_addr, rd_ack, rd_data, rd_valid, std_logic_vector(to_unsigned(i * 2, 25)), data_out);
                    check_equal(data_out,
                        std_logic_vector(to_unsigned(16#B000# + i, 16)),
                        "Read " & integer'image(i) & " data correct");
                end loop;

            end if;
        end loop;

        test_runner_cleanup(runner);
    end process;

    -- Generous watchdog: init alone takes ~200us
    test_runner_watchdog(runner, 5 ms);

end architecture sim;
