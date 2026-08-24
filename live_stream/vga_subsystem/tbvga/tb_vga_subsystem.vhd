-- =============================================================================
-- tb_vga_subsystem.vhd
-- VUnit testbench for vga_subsystem.vhd (integration test)
--
-- Exercises the full internal pipeline:
--   asyn_fifo (100MHz write) -> vga_core (25MHz) -> vga_interface (25MHz)
--
-- The TB drives pixels in at 100MHz and observes the VGA DAC output.
--
-- Tests:
--   tc_reset_outputs   : VGA outputs safe after reset
--   tc_fifo_backpressure: fifo_full asserts when FIFO overflows
--   tc_pixel_appears   : pixel written at 100MHz appears on DAC output
--   tc_hsync_present   : hsync pulses observed within one frame time
--   tc_vsync_present   : vsync pulse observed within one frame time
--   tc_no_output_blank : DAC=0 during blanking, non-zero in active
--   tc_continuous_fill : continuous 100MHz write keeps FIFO fed
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_vga_subsystem is
    generic (runner_cfg : string);
end entity;

architecture sim of tb_vga_subsystem is

    constant T_25M  : time := 40 ns;
    constant T_100M : time := 10 ns;

    signal clk_25m      : std_logic := '0';
    signal clk_100m     : std_logic := '0';
    signal rst_n        : std_logic := '0';

    signal fifo_wr_en   : std_logic := '0';
    signal fifo_wr_data : std_logic_vector(15 downto 0) := (others => '0');
    signal fifo_full    : std_logic;

    signal vga_r        : std_logic_vector(3 downto 0);
    signal vga_g        : std_logic_vector(3 downto 0);
    signal vga_b        : std_logic_vector(3 downto 0);
    signal vga_hs       : std_logic;
    signal vga_vs       : std_logic;

    -- VGA timing constants
    constant H_TOTAL    : integer := 800;
    constant V_TOTAL    : integer := 525;
    constant H_ACTIVE   : integer := 640;
    constant V_ACTIVE   : integer := 480;

    procedure clk25_wait(n : natural) is
    begin
        for i in 1 to n loop wait until rising_edge(clk_25m); end loop;
    end procedure;

    procedure clk130_wait(n : natural) is
    begin
        for i in 1 to n loop wait until rising_edge(clk_100m); end loop;
    end procedure;

    procedure do_reset(signal rst_n_out : out std_logic) is
    begin
        rst_n_out <= '0';
        clk25_wait(8); clk130_wait(8);
        rst_n_out <= '1';
        clk25_wait(4); clk130_wait(4);
    end procedure;

    function rgb565(r5, g6, b5 : natural) return std_logic_vector is
    begin
        return std_logic_vector(
            to_unsigned(r5, 5) & to_unsigned(g6, 6) & to_unsigned(b5, 5)
        );
    end function;

    -- Write n pixels into the subsystem FIFO at 100MHz
    procedure fill_fifo(
        signal wr_data_out : out std_logic_vector(15 downto 0);
        signal wr_en_out   : out std_logic;
        signal full_in     : in  std_logic;
        count              : natural;
        pixel              : std_logic_vector(15 downto 0)
    ) is
    begin
        for i in 0 to count-1 loop
            wait until rising_edge(clk_100m);
            if full_in = '0' then
                wr_data_out <= pixel;
                wr_en_out   <= '1';
            end if;
        end loop;
        wait until rising_edge(clk_100m);
        wr_en_out <= '0';
    end procedure;

begin

    clk_25m  <= not clk_25m  after T_25M  / 2;
    clk_100m <= not clk_100m after T_100M / 2;

    u_dut : entity work.vga_subsystem
        port map (
            clk_25m      => clk_25m,
            clk_130m     => clk_100m,
            rst_n        => rst_n,
            test_mode    => "00",
            fifo_wr_en   => fifo_wr_en,
            fifo_wr_data => fifo_wr_data,
            fifo_full    => fifo_full,
            vga_r        => vga_r,
            vga_g        => vga_g,
            vga_b        => vga_b,
            vga_hs       => vga_hs,
            vga_vs       => vga_vs
        );

    main : process
        variable hsync_seen  : boolean;
        variable vsync_seen  : boolean;
        variable active_r_ok : boolean;
        variable blank_ok    : boolean;
        variable r_nonzero   : boolean;
        variable full_seen   : boolean;
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            -- -----------------------------------------------------------------
            if run("tc_reset_outputs") then
                info("After reset: all VGA outputs in safe state");
                rst_n <= '0';
                clk25_wait(10);
                -- hs/vs idle high (monitor safe)
                check_equal(vga_hs, std_logic'('1'), "HS idle high in reset");
                check_equal(vga_vs, std_logic'('1'), "VS idle high in reset");
                -- DAC outputs black
                check_equal(vga_r, std_logic_vector'("0000"), "R=0 in reset");
                check_equal(vga_g, std_logic_vector'("0000"), "G=0 in reset");
                check_equal(vga_b, std_logic_vector'("0000"), "B=0 in reset");

            -- -----------------------------------------------------------------
            elsif run("tc_fifo_backpressure") then
                info("fifo_full asserts when FIFO saturated");
                do_reset(rst_n);
                clk130_wait(10);
                full_seen := false;
                -- VGA now consumes one source pixel per 2x2 output block
                -- while this test writes, so exceed one physical FIFO depth
                -- to exercise the actual back-pressure path.
                for i in 0 to 8191 loop
                    wait until rising_edge(clk_100m);
                    if fifo_full = '0' then
                        fifo_wr_data <= std_logic_vector(to_unsigned(i mod 65536, 16));
                        fifo_wr_en   <= '1';
                    else
                        fifo_wr_en <= '0';
                        full_seen  := true;
                        exit;
                    end if;
                end loop;
                wait until rising_edge(clk_100m);
                fifo_wr_en <= '0';
                -- Allow CDC sync into write domain
                clk130_wait(6);
                check(full_seen, "fifo_full must assert while continuously writing");

            -- -----------------------------------------------------------------
            elsif run("tc_hsync_present") then
                info("HSYNC pulses observed within one scan line time");
                do_reset(rst_n);
                -- Run one full line and check hsync goes low at least once
                hsync_seen := false;
                for i in 0 to H_TOTAL loop
                    wait until rising_edge(clk_25m);
                    if vga_hs = '0' then
                        hsync_seen := true;
                    end if;
                end loop;
                check(hsync_seen, "HSYNC must pulse low within one line");

            -- -----------------------------------------------------------------
            elsif run("tc_vsync_present") then
                info("VSYNC pulse observed within one full frame");
                do_reset(rst_n);
                vsync_seen := false;
                -- Run two full frames to guarantee we catch the pulse
                for i in 0 to H_TOTAL * V_TOTAL * 2 loop
                    wait until rising_edge(clk_25m);
                    if vga_vs = '0' then
                        vsync_seen := true;
                    end if;
                end loop;
                check(vsync_seen, "VSYNC must pulse low within 2 frames");

            -- -----------------------------------------------------------------
            elsif run("tc_no_output_blank") then
                info("DAC=0 during blanking, non-zero in active region");
                do_reset(rst_n);
                -- Pre-fill FIFO with pure red pixels (R=max)
                fill_fifo(fifo_wr_data, fifo_wr_en, fifo_full, 1024, rgb565(31, 0, 0));
                -- Also start continuous fill in background would be complex
                -- so just check blanking region stays zero first
                -- Run to first blanking region (past hc=640 before reset)
                -- since we just reset, counters start at 0 which is active
                -- Wait until first blanking (hc >= 640)
                blank_ok   := false;
                r_nonzero  := false;

                for i in 0 to H_TOTAL * 2 loop
                    wait until rising_edge(clk_25m);
                    if vga_r = "0000" and vga_g = "0000" and vga_b = "0000" then
                        blank_ok := true;
                    end if;
                    if vga_r /= "0000" then
                        r_nonzero := true;
                    end if;
                end loop;

                check(blank_ok,  "DAC must be 0 in blanking region");
                check(r_nonzero, "DAC must be non-zero in active region with red pixels");

            -- -----------------------------------------------------------------
            elsif run("tc_pixel_appears") then
                info("Pixel written at 100MHz appears on VGA DAC output");
                do_reset(rst_n);
                clk130_wait(10);
                -- Write a full line + some extra of pure blue pixels
                fill_fifo(fifo_wr_data, fifo_wr_en, fifo_full, 800, rgb565(0, 0, 31));
                -- Wait up to 2 lines for blue to appear on DAC
                r_nonzero := false;
                for i in 0 to H_TOTAL * 4 loop
                    wait until rising_edge(clk_25m);
                    -- Blue max = B[4:1] = "1111"
                    if vga_b = "1111" then
                        r_nonzero := true;
                    end if;
                end loop;
                check(r_nonzero,
                      "Blue pixels must appear on DAC after CDC FIFO");

            -- -----------------------------------------------------------------
            elsif run("tc_continuous_fill") then
                info("Continuous 100MHz writes keep FIFO fed without underrun");
                do_reset(rst_n);
                -- Start a background process that continuously writes white pixels
                -- We check that fifo_full never gets stuck permanently
                -- Write 2 complete lines at 100MHz
                for i in 0 to H_TOTAL * 2 - 1 loop
                    wait until rising_edge(clk_100m);
                    fifo_wr_data <= rgb565(31, 63, 31);
                    fifo_wr_en   <= '1' when fifo_full = '0' else '0';
                end loop;
                wait until rising_edge(clk_100m);
                fifo_wr_en <= '0';

                -- Run the VGA side for a full line to drain the FIFO
                clk25_wait(H_TOTAL);

                -- FIFO should have drained somewhat — full should deassert
                clk25_wait(4);
                check_equal(fifo_full, std_logic'('0'),
                            "FIFO must drain after VGA reads for one line");

            end if;
        end loop;

        test_runner_cleanup(runner);
    end process;

    test_runner_watchdog(runner, 100 ms);

end architecture sim;
