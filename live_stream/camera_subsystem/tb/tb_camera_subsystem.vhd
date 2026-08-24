-- =============================================================================
-- tb_camera_subsystem.vhd
-- VUnit testbench for camera_subsystem.vhd (integration test)
--
-- Tests the full subsystem:
--   i2c_top -> camera_interface -> asyn_fifo
--
-- The testbench acts as:
--   1. OV7670 camera stimulus (PCLK, VSYNC, HREF, D[7:0])
--   2. SDRAM subsystem (reads from FIFO at 100 MHz)
--
-- Tests:
--   tc_xclk_present         : cam_xclk toggles at 24MHz
--   tc_pwdn_low             : cam_pwdn always '0'
--   tc_cam_held_in_reset    : cam_rst_n low at startup
--   tc_cam_releases         : cam_rst_n goes high before SCCB starts
--   tc_no_capture_before_i2c: FIFO empty before i2c config done
--   tc_fifo_fills_after_i2c : pixels appear in FIFO after i2c_done + frame
--   tc_cdc_pixel_integrity  : pixel written at PCLK readable at 100MHz
--   tc_frame_done_sync      : frame_done pulse visible from PCLK domain
--   tc_fifo_empty_between   : FIFO empties between frames at 100MHz drain rate
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_camera_subsystem is
    generic (runner_cfg : string);
end entity;

architecture sim of tb_camera_subsystem is

    -- Clock periods
    constant T_24M  : time := 41667 ps;   -- 24 MHz PLL / XCLK
    constant T_PCLK : time := 41667 ps;   -- OV7670 PCLK (same rate)
    constant T_100M : time := 10 ns;      -- 100 MHz SDRAM read side

    -- OV7670 frame constants (small frame for fast simulation)
    constant SIM_H_PIX  : integer := 32;   -- pixels per line (sim only)
    constant SIM_V_LINE : integer := 4;    -- lines per frame  (sim only)
    constant H_BLANK_CY : integer := 20;   -- blank clocks between lines

    -- Clocks
    signal clk_24m  : std_logic := '0';
    signal clk_100m : std_logic := '0';
    signal cam_pclk : std_logic := '0';   -- driven independently by TB
    signal rst_n    : std_logic := '0';

    -- OV7670 stimulus signals
    signal cam_vsync : std_logic := '0';
    signal cam_href  : std_logic := '0';
    signal cam_d     : std_logic_vector(7 downto 0) := (others => '0');

    -- DUT outputs -> GPIO
    signal cam_xclk  : std_logic;
    signal cam_sioc  : std_logic;
    signal cam_siod  : std_logic;
    signal cam_rst_n : std_logic;
    signal cam_pwdn  : std_logic;

    -- FIFO read side (100 MHz domain)
    signal fifo_rd_en   : std_logic := '0';
    signal fifo_rd_data : std_logic_vector(15 downto 0);
    signal fifo_empty   : std_logic;

    -- Frame done
    signal frame_done   : std_logic;

    -- Status
    signal i2c_done_obs : std_logic;

    -- Pull-up for open-drain SIOD
    signal siod_pulled  : std_logic;

    -- Pixel verification
    signal pixels_read  : integer := 0;

    procedure clk24_wait(n : natural) is
    begin
        for i in 1 to n loop wait until rising_edge(clk_24m); end loop;
    end procedure;

    procedure clk130_wait(n : natural) is
    begin
        for i in 1 to n loop wait until rising_edge(clk_100m); end loop;
    end procedure;

    procedure pclk_wait(n : natural) is
    begin
        for i in 1 to n loop wait until rising_edge(cam_pclk); end loop;
    end procedure;

    -- Drive one complete scan line into the subsystem
    procedure drive_line(
        signal cam_href : out std_logic;
        signal cam_d    : out std_logic_vector(7 downto 0);
        pixels          : integer;
        base_val        : natural
    ) is
        variable b0 : std_logic_vector(7 downto 0);
        variable b1 : std_logic_vector(7 downto 0);
    begin
        cam_href <= '1';
        for px in 0 to pixels-1 loop
            b0 := std_logic_vector(to_unsigned((base_val + px) mod 256, 8));
            b1 := std_logic_vector(to_unsigned(255 - (base_val + px) mod 256, 8));
            cam_d <= b0; wait until rising_edge(cam_pclk);
            cam_d <= b1; wait until rising_edge(cam_pclk);
        end loop;
        cam_href <= '0';
        cam_d    <= (others => '0');
        pclk_wait(H_BLANK_CY);
    end procedure;

    -- Drive one complete small frame
    procedure drive_frame(
        signal cam_vsync : out std_logic;
        signal cam_href  : out std_logic;
        signal cam_d     : out std_logic_vector(7 downto 0);
        lines, pixels    : integer;
        base             : natural
    ) is
    begin
        cam_vsync <= '1';
        pclk_wait(10);
        cam_vsync <= '0';
        for ln in 0 to lines-1 loop
            drive_line(cam_href, cam_d, pixels, (base + ln * pixels) mod 256);
        end loop;
    end procedure;

    -- Drain FIFO at 100MHz and count pixels read
    procedure drain_fifo(
        signal fifo_rd_en  : out std_logic;
        signal pixels_read : inout integer;
        max_pixels         : integer
    ) is
        variable cnt : integer := 0;
    begin
        while fifo_empty = '0' and cnt < max_pixels loop
            wait until rising_edge(clk_100m);
            fifo_rd_en <= '1';
            wait until rising_edge(clk_100m);
            fifo_rd_en <= '0';
            clk130_wait(2);
            cnt := cnt + 1;
            pixels_read <= pixels_read + 1;
        end loop;
        fifo_rd_en <= '0';
    end procedure;

begin

    -- Free-running clocks
    clk_24m  <= not clk_24m  after T_24M  / 2;
    clk_100m <= not clk_100m after T_100M / 2;
    cam_pclk <= not cam_pclk after T_PCLK / 2;   -- independent from clk_24m

    siod_pulled <= 'H' when cam_siod = 'Z' else cam_siod;

    -- =========================================================================
    -- DUT
    -- =========================================================================
    u_dut : entity work.camera_subsystem
        port map (
            clk_24m      => clk_24m,
            clk_130m     => clk_100m,
            rst_n        => rst_n,
            invert_sync  => '0',
            reverse_bits => '0',
            data_map_sel => "00",
            swap_bytes   => '0',
            cam_pclk     => cam_pclk,
            cam_vsync    => cam_vsync,
            cam_href     => cam_href,
            cam_d        => cam_d,
            cam_xclk     => cam_xclk,
            cam_sioc     => cam_sioc,
            cam_siod     => cam_siod,
            cam_rst_n    => cam_rst_n,
            cam_pwdn     => cam_pwdn,
            fifo_rd_en   => fifo_rd_en,
            fifo_rd_data => fifo_rd_data,
            fifo_empty   => fifo_empty,
            fifo_rd_usedw => open,
            frame_done   => frame_done,
            i2c_done     => i2c_done_obs,
            pclk_heartbeat => open
        );

    -- =========================================================================
    main : process
        variable t_start    : time;
        variable t_end      : time;
        variable pix_before : integer;
        variable rd_data_0  : std_logic_vector(15 downto 0);
        variable xclk_cnt   : integer;
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            -- -----------------------------------------------------------------
            if run("tc_xclk_present") then
                info("cam_xclk must toggle at 24MHz");
                rst_n <= '0'; clk24_wait(4);
                rst_n <= '1';
                for i in 0 to 4 loop
                    wait until rising_edge(clk_24m);
                    wait for 0 ns;
                    check_equal(cam_xclk, '1', "cam_xclk high on clk_24m rising");
                    wait until falling_edge(clk_24m);
                    wait for 0 ns;
                    check_equal(cam_xclk, '0', "cam_xclk low on clk_24m falling");
                end loop;

            -- -----------------------------------------------------------------
            elsif run("tc_pwdn_low") then
                info("cam_pwdn must always be '0' (camera powered)");
                rst_n <= '0'; clk24_wait(4);
                check_equal(cam_pwdn, '0', "pwdn=0 in reset");
                rst_n <= '1'; clk24_wait(100);
                check_equal(cam_pwdn, '0', "pwdn=0 after reset");

            -- -----------------------------------------------------------------
            elsif run("tc_cam_held_in_reset") then
                info("cam_rst_n must be '0' at startup (hardware reset hold)");
                rst_n <= '0'; clk24_wait(4);
                rst_n <= '1';
                -- Immediately after releasing rst_n, cam_rst_n must still be low
                clk24_wait(5);
                check_equal(cam_rst_n, '0',
                    "cam_rst_n must be held low during reset hold period");

            -- -----------------------------------------------------------------
            elsif run("tc_cam_releases") then
                info("cam_rst_n goes high after reset hold, before SCCB starts");
                rst_n <= '0'; clk24_wait(4);
                rst_n <= '1';
                -- Wait for cam_rst_n to release (5ms @ 24MHz = 120000 cycles)
                wait until cam_rst_n = '1' for 7 ms;
                check_equal(cam_rst_n, '1',
                    "cam_rst_n must release within 7ms");
                -- cam_rst_n must rise before SIOC starts toggling
                -- (i.e. before SCCB begins)
                check_equal(i2c_done_obs, '0',
                    "i2c_done must still be 0 right after cam_rst_n releases");

            -- -----------------------------------------------------------------
            elsif run("tc_no_capture_before_i2c") then
                info("FIFO must stay empty before i2c_done");
                rst_n <= '0'; clk24_wait(4);
                rst_n <= '1';
                -- Drive VSYNC/HREF/DATA while i2c is still running
                clk24_wait(50);
                cam_vsync <= '1'; pclk_wait(10);
                cam_vsync <= '0';
                drive_line(cam_href, cam_d, SIM_H_PIX, 0);
                -- FIFO must be empty (camera_interface gated on i2c_done)
                clk130_wait(10);
                check_equal(fifo_empty, '1',
                    "FIFO must be empty before i2c_done asserts");

            -- -----------------------------------------------------------------
            elsif run("tc_fifo_fills_after_i2c") then
                info("Pixels appear in FIFO after i2c completes + frame driven");
                rst_n <= '0'; clk24_wait(4);
                rst_n <= '1';
                -- Wait for i2c to complete (~19ms total: reset + writes)
                wait until i2c_done_obs = '1' for 45 ms;
                check_equal(i2c_done_obs, '1',
                    "i2c_done must assert within 45ms");
                -- Now drive a small frame
                drive_frame(cam_vsync, cam_href, cam_d, SIM_V_LINE, SIM_H_PIX, 0);
                -- Allow CDC to propagate
                clk130_wait(20);
                check_equal(fifo_empty, '0',
                    "FIFO must have pixels after frame + i2c_done");

            -- -----------------------------------------------------------------
            elsif run("tc_cdc_pixel_integrity") then
                info("Pixel written at PCLK readable correctly at 100MHz");
                rst_n <= '0'; clk24_wait(4);
                rst_n <= '1';
                wait until i2c_done_obs = '1' for 45 ms;
                -- Drive a known pixel: byte0=0xF8, byte1=0x1F -> 0xF81F
                cam_vsync <= '1'; pclk_wait(10);
                cam_vsync <= '0';
                cam_href  <= '1';
                cam_d     <= x"F8"; wait until rising_edge(cam_pclk);
                cam_d     <= x"1F"; wait until rising_edge(cam_pclk);
                cam_href  <= '0';
                -- Allow CDC
                clk130_wait(15);
                wait until fifo_empty = '0' for 100 us;
                -- Read from 100MHz side
                wait until rising_edge(clk_100m);
                fifo_rd_en <= '1';
                wait until rising_edge(clk_100m);
                fifo_rd_en <= '0';
                clk130_wait(2);
                check_equal(fifo_rd_data,
                    std_logic_vector'(x"F81F"),
                    "CDC pixel integrity: 0xF8,0x1F -> 0xF81F at 100MHz");

            -- -----------------------------------------------------------------
            elsif run("tc_frame_done_sync") then
                info("frame_done pulses at end of each frame");
                rst_n <= '0'; clk24_wait(4);
                rst_n <= '1';
                wait until i2c_done_obs = '1' for 45 ms;
                -- Drive frame, wait for frame_done
                drive_frame(cam_vsync, cam_href, cam_d, SIM_V_LINE, SIM_H_PIX, 0);
                cam_vsync <= '1';
                wait until frame_done = '1' for 100 us;
                check_equal(frame_done, '1',
                    "frame_done must pulse at frame end");

            -- -----------------------------------------------------------------
            elsif run("tc_fifo_empty_between") then
                info("FIFO drains to empty between frames at 100MHz read rate");
                rst_n <= '0'; clk24_wait(4);
                rst_n <= '1';
                wait until i2c_done_obs = '1' for 45 ms;
                -- Drive one frame
                drive_frame(cam_vsync, cam_href, cam_d, SIM_V_LINE, SIM_H_PIX, 0);
                clk130_wait(20);
                -- Drain everything at 100MHz
                drain_fifo(fifo_rd_en, pixels_read, SIM_H_PIX * SIM_V_LINE + 10);
                clk130_wait(20);
                check_equal(fifo_empty, '1',
                    "FIFO must empty between frames after 100MHz drain");

            end if;
        end loop;

        test_runner_cleanup(runner);
    end process;

    -- Generous watchdog: i2c_done tests need ~45ms
    test_runner_watchdog(runner, 90 ms);

end architecture sim;
