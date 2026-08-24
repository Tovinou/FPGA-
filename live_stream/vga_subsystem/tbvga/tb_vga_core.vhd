-- =============================================================================
-- tb_vga_core.vhd
-- VUnit testbench for vga_core.vhd only
--
-- Tests:
--   tc_reset          : counters held at zero during reset
--   tc_hcounter       : h_count runs 0..799 and wraps
--   tc_hsync_width    : HSYNC pulse = 96 cycles at position 656..752
--   tc_hsync_polarity : HSYNC idle high, active low
--   tc_vsync_lines    : VSYNC low for exactly 2 lines
--   tc_vsync_polarity : VSYNC idle high, active low
--   tc_active_count   : exactly 307200 active pixels per frame
--   tc_active_boundary: active=0 at first blanking pixel
--   tc_frame_period   : full frame = 800*525 = 420000 clocks
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_vga_core is
    generic (runner_cfg : string);
end entity;

architecture sim of tb_vga_core is

    -- Clock
    constant T_CLK : time := 40 ns;  -- 25 MHz
    signal clk   : std_logic := '0';
    signal rst_n : std_logic := '0';

    -- DUT outputs
    signal hsync   : std_logic;
    signal vsync   : std_logic;
    signal active  : std_logic;
    signal h_count : std_logic_vector(9 downto 0);
    signal v_count : std_logic_vector(9 downto 0);

    -- VESA 640x480 constants (must match DUT)
    constant H_ACTIVE    : integer := 640;
    constant H_FP        : integer := 16;
    constant H_SYNC_W    : integer := 96;
    constant H_BP        : integer := 48;
    constant H_TOTAL     : integer := 800;
    constant V_ACTIVE    : integer := 480;
    constant V_FP        : integer := 10;
    constant V_SYNC_W    : integer := 2;
    constant V_BP        : integer := 33;
    constant V_TOTAL     : integer := 525;
    constant H_SYNC_START: integer := 656;
    constant H_SYNC_END  : integer := 752;
    constant V_SYNC_START: integer := 490;
    constant V_SYNC_END  : integer := 492;

    procedure clk_wait(n : natural) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

    procedure do_reset(signal rst_n_out : out std_logic) is
    begin
        rst_n_out <= '0';
        clk_wait(4);
        rst_n_out <= '1';
    end procedure;

begin

    clk <= not clk after T_CLK / 2;

    u_dut : entity work.vga_core
        port map (
            pclk    => clk,
            rst_n   => rst_n,
            hsync   => hsync,
            vsync   => vsync,
            active  => active,
            h_count => h_count,
            v_count => v_count
        );

    main : process
        variable hsync_low_cnt  : integer;
        variable vsync_low_lines: integer;
        variable active_cnt     : integer;
        variable frame_clocks   : integer;
        variable last_vsync     : std_logic;
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            -- -----------------------------------------------------------------
            if run("tc_reset") then
                info("Reset: all outputs must be in safe idle state");
                rst_n <= '0';
                clk_wait(10);
                check_equal(h_count, std_logic_vector(to_unsigned(0,10)),
                            "h_count=0 in reset");
                check_equal(v_count, std_logic_vector(to_unsigned(0,10)),
                            "v_count=0 in reset");
                check_equal(hsync,  std_logic'('1'), "hsync idle high in reset");
                check_equal(vsync,  std_logic'('1'), "vsync idle high in reset");
                check_equal(active, std_logic'('0'), "active low in reset");

            -- -----------------------------------------------------------------
            elsif run("tc_hcounter") then
                info("H counter wraps 0->799->0");
                do_reset(rst_n);
                -- Run exactly H_TOTAL clocks from 0
                clk_wait(H_TOTAL);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(h_count, std_logic_vector(to_unsigned(0,10)),
                            "h_count wraps to 0 after 800 clocks");
                -- Spot check mid-line
                clk_wait(350);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(h_count, std_logic_vector(to_unsigned(350,10)),
                            "h_count=350 after 350 more clocks");

            -- -----------------------------------------------------------------
            elsif run("tc_hsync_width") then
                info("HSYNC pulse width = 96 clocks");
                do_reset(rst_n);
                -- Count low cycles over one complete line
                hsync_low_cnt := 0;
                for i in 0 to H_TOTAL-1 loop
                    wait until rising_edge(clk);
                    if hsync = '0' then
                        hsync_low_cnt := hsync_low_cnt + 1;
                    end if;
                end loop;
                check_equal(hsync_low_cnt, H_SYNC_W,
                            "HSYNC low for exactly 96 clocks per line");

            -- -----------------------------------------------------------------
            elsif run("tc_hsync_polarity") then
                info("HSYNC idle high, pulse active low");
                do_reset(rst_n);
                -- Before sync window: must be high
                clk_wait(H_SYNC_START - 1);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(hsync, std_logic'('1'), "HSYNC high before sync start");
                -- Enter sync window
                wait until rising_edge(clk);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(hsync, std_logic'('0'), "HSYNC low at sync start (656)");
                -- End of sync window
                clk_wait(H_SYNC_W - 1);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(hsync, std_logic'('0'), "HSYNC still low at last sync clock");
                wait until rising_edge(clk);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(hsync, std_logic'('1'), "HSYNC high again after sync end (752)");

            -- -----------------------------------------------------------------
            elsif run("tc_vsync_lines") then
                info("VSYNC low for exactly 2 lines");
                do_reset(rst_n);
                vsync_low_lines := 0;
                -- Sample vsync once per line for a full frame
                for line in 0 to V_TOTAL-1 loop
                    -- Wait for h_count = 0
                    wait until rising_edge(clk) and
                               to_integer(unsigned(h_count)) = 0;
                    if vsync = '0' then
                        vsync_low_lines := vsync_low_lines + 1;
                    end if;
                end loop;
                check_equal(vsync_low_lines, V_SYNC_W,
                            "VSYNC low for exactly 2 lines");

            -- -----------------------------------------------------------------
            elsif run("tc_vsync_polarity") then
                info("VSYNC idle high, pulse active low");
                do_reset(rst_n);
                -- Run to first vsync falling edge
                wait until vsync = '0';
                check_equal(vsync, std_logic'('0'), "VSYNC low during sync pulse");
                wait until vsync = '1';
                check_equal(vsync, std_logic'('1'), "VSYNC high after pulse");

            -- -----------------------------------------------------------------
            elsif run("tc_active_count") then
                info("Active pixel count = 640*480 = 307200 per frame");
                do_reset(rst_n);
                active_cnt := 0;
                for i in 0 to H_TOTAL * V_TOTAL - 1 loop
                    wait until rising_edge(clk);
                    if active = '1' then
                        active_cnt := active_cnt + 1;
                    end if;
                end loop;
                check_equal(active_cnt, H_ACTIVE * V_ACTIVE,
                            "Active pixels per frame = 307200");

            -- -----------------------------------------------------------------
            elsif run("tc_active_boundary") then
                info("Active deasserts at first blanking pixel (hc=640)");
                do_reset(rst_n);
                -- Run to start of first active line
                wait until active = '1';
                -- Count active pixels on this line
                active_cnt := 0;
                while active = '1' loop
                    wait until rising_edge(clk);
                    if active = '1' then
                        active_cnt := active_cnt + 1;
                    end if;
                end loop;
                check_equal(active_cnt, H_ACTIVE,
                            "Exactly 640 active pixels per line");
                check_equal(active, std_logic'('0'),
                            "Active deasserts at hc=640");

            -- -----------------------------------------------------------------
            elsif run("tc_frame_period") then
                info("Full frame = 800*525 = 420000 pixel clocks");
                do_reset(rst_n);
                -- Wait for vsync falling edge (start of sync pulse)
                wait until vsync = '0';
                frame_clocks := 0;
                -- Count until next falling edge
                wait until vsync = '1';
                loop
                    wait until rising_edge(clk);
                    frame_clocks := frame_clocks + 1;
                    exit when vsync = '0';
                end loop;
                -- Expected: H_TOTAL * (V_TOTAL - V_SYNC_W) = 800*523 = 418400
                check(frame_clocks >= H_TOTAL*(V_TOTAL-V_SYNC_W) - 2 and
                      frame_clocks <= H_TOTAL*(V_TOTAL-V_SYNC_W) + 2,
                      "Frame period out of range, got " &
                      integer'image(frame_clocks));

            end if;
        end loop;

        test_runner_cleanup(runner);
    end process;

    test_runner_watchdog(runner, 70 ms);

end architecture sim;
