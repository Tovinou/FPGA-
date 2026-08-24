-- =============================================================================
-- tb_camera_interface.vhd
-- VUnit testbench for camera_interface.vhd (corrected version)
--
-- Simulates OV7670 signal timing: VSYNC, HREF, D[7:0]
-- Verifies pixel assembly, FIFO write timing, and state machine behaviour.
--
-- Tests:
--   tc_reset_idle          : no output during reset
--   tc_wait_config         : no capture before i2c_done
--   tc_vsync_gate          : capture only starts after VSYNC high->low
--   tc_pixel_assembly      : two bytes assembled correctly into RGB565
--   tc_byte_order          : D[7:0] byte0=high, byte1=low (RGB565 order)
--   tc_href_alignment      : byte_sel resets on falling HREF
--   tc_fifo_full_drop      : pixel dropped when FIFO full, no wr_en
--   tc_frame_done_pulse    : frame_done asserts on VSYNC rising in S_CAPTURE
--   tc_frame_done_width    : frame_done held >= 2 PCLK cycles
--   tc_multi_frame         : consecutive frames captured without gaps
--   tc_full_line           : decimation: 640 pixels per line -> 320 wr_en pulses
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_camera_interface is
    generic (runner_cfg : string);
end entity;

architecture sim of tb_camera_interface is

    constant T_PCLK : time := 41667 ps;   -- 24 MHz OV7670 PCLK

    -- OV7670 640x480 timing constants
    constant H_PIXELS    : integer := 640;
    constant V_LINES     : integer := 480;
    -- Blanking periods (approximate OV7670 timing)
    constant H_BLANK     : integer := 144;   -- clocks between lines
    constant V_BLANK_LN  : integer := 3;     -- VSYNC high lines (approximate)

    signal pclk       : std_logic := '0';
    signal rst_n      : std_logic := '0';
    signal i2c_done   : std_logic := '0';
    signal vsync      : std_logic := '0';
    signal href       : std_logic := '0';
    signal cam_data   : std_logic_vector(7 downto 0) := (others => '0');

    signal fifo_wr_en   : std_logic;
    signal fifo_wr_data : std_logic_vector(15 downto 0);
    signal fifo_full    : std_logic := '0';
    signal frame_done   : std_logic;

    -- Pixel capture verification
    signal pixel_count  : integer := 0;
    signal wr_en_count  : integer := 0;

    procedure pclk_wait(n : natural) is
    begin
        for i in 1 to n loop
            wait until rising_edge(pclk);
        end loop;
    end procedure;

    procedure do_reset(
        signal rst_n    : out std_logic;
        signal i2c_done : out std_logic;
        signal vsync    : out std_logic;
        signal href     : out std_logic
    ) is
    begin
        rst_n    <= '0';
        i2c_done <= '0';
        vsync    <= '0';
        href     <= '0';
        pclk_wait(8);
        rst_n <= '1';
        pclk_wait(4);
    end procedure;

    -- Drive one complete OV7670 scan line
    -- Each pixel = 2 bytes on D[7:0] with href=1
    -- After last pixel: href falls, blank clocks with href=0
    procedure drive_line(
        signal href     : out std_logic;
        signal cam_data : out std_logic_vector(7 downto 0);
        pixels          : integer;
        start_val       : natural;
        h_blank_cy      : integer
    ) is
        variable byte0 : std_logic_vector(7 downto 0);
        variable byte1 : std_logic_vector(7 downto 0);
        variable val   : natural;
    begin
        href <= '1';
        for px in 0 to pixels-1 loop
            val   := (start_val + px) mod 256;
            byte0 := std_logic_vector(to_unsigned(val, 8));
            byte1 := std_logic_vector(to_unsigned(255 - val, 8));
            -- First byte
            cam_data <= byte0;
            wait until rising_edge(pclk);
            -- Second byte
            cam_data <= byte1;
            wait until rising_edge(pclk);
        end loop;
        -- End of line
        href     <= '0';
        cam_data <= (others => '0');
        pclk_wait(h_blank_cy);
    end procedure;

    -- Drive one complete OV7670 frame
    -- VSYNC high during blanking, low during active image
    procedure drive_frame(
        signal vsync    : out std_logic;
        signal href     : out std_logic;
        signal cam_data : out std_logic_vector(7 downto 0);
        lines           : integer;
        pixels          : integer;
        start_val       : natural
    ) is
    begin
        -- VSYNC high = frame blanking start
        vsync <= '1';
        href  <= '0';
        pclk_wait(V_BLANK_LN * (pixels*2 + H_BLANK));
        -- VSYNC low = active image starts
        vsync <= '0';
        for ln in 0 to lines-1 loop
            drive_line(href, cam_data, pixels, (start_val + ln * pixels) mod 256, H_BLANK);
        end loop;
    end procedure;

    -- Verify assembled pixel from byte0 and byte1
    function expected_pixel(b0, b1 : std_logic_vector(7 downto 0))
        return std_logic_vector is
    begin
        return b0 & b1;
    end function;

begin

    pclk <= not pclk after T_PCLK / 2;

    u_dut : entity work.camera_interface
        port map (
            clk          => '0',
            pclk         => pclk,
            rst_n        => rst_n,
            i2c_done     => i2c_done,
            invert_sync  => '0',
            reverse_bits => '0',
            data_map_sel => "00",
            swap_bytes   => '0',
            vsync        => vsync,
            href         => href,
            cam_data     => cam_data,
            fifo_wr_en   => fifo_wr_en,
            fifo_wr_data => fifo_wr_data,
            fifo_full    => fifo_full,
            frame_done   => frame_done,
            pclk_heartbeat => open
        );

    -- =========================================================================
    -- Pixel counter process (counts successful FIFO writes)
    -- =========================================================================
    p_count : process(pclk)
    begin
        if rising_edge(pclk) then
            if fifo_wr_en = '1' then
                wr_en_count <= wr_en_count + 1;
            end if;
        end if;
    end process;

    -- =========================================================================
    main : process
        variable pix_before  : integer;
        variable pix_after   : integer;
        variable fd_cycles   : integer;
        variable last_fd     : std_logic;
        variable b0, b1      : std_logic_vector(7 downto 0);
        variable exp_pix     : std_logic_vector(15 downto 0);
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            -- -----------------------------------------------------------------
            if run("tc_reset_idle") then
                info("No output during reset");
                rst_n    <= '0';
                i2c_done <= '1';
                vsync    <= '1';
                href     <= '1';
                cam_data <= x"AB";
                pclk_wait(20);
                check_equal(fifo_wr_en, '0', "wr_en=0 in reset");
                check_equal(frame_done, '0', "frame_done=0 in reset");

            -- -----------------------------------------------------------------
            elsif run("tc_wait_config") then
                info("No capture before i2c_done asserts");
                do_reset(rst_n, i2c_done, vsync, href);
                -- i2c_done still '0' — drive full VSYNC/HREF/DATA sequence
                vsync    <= '1';
                pclk_wait(10);
                vsync    <= '0';
                href     <= '1';
                cam_data <= x"AA";
                pclk_wait(4);
                cam_data <= x"BB";
                pclk_wait(4);
                href     <= '0';
                pclk_wait(4);
                -- No pixels should have been captured
                check_equal(wr_en_count, 0,
                    "wr_en must not assert before i2c_done");
                check_equal(frame_done, '0',
                    "frame_done must not assert before i2c_done");

            -- -----------------------------------------------------------------
            elsif run("tc_vsync_gate") then
                info("Capture only starts after VSYNC high->low transition");
                do_reset(rst_n, i2c_done, vsync, href);
                i2c_done <= '1';
                -- Drive HREF without VSYNC first — should not capture
                href     <= '1';
                cam_data <= x"CC";
                pclk_wait(10);
                check_equal(wr_en_count, 0,
                    "wr_en must not assert before first VSYNC");
                -- Now drive proper VSYNC
                href  <= '0';
                vsync <= '1';
                pclk_wait(6);
                vsync <= '0';
                -- Now drive one pixel pair
                href     <= '1';
                cam_data <= x"12";
                pclk_wait(1);
                cam_data <= x"34";
                pclk_wait(1);
                href     <= '0';
                pclk_wait(4);
                check_equal(wr_en_count, 1,
                    "Exactly 1 pixel written after valid VSYNC sequence");

            -- -----------------------------------------------------------------
            elsif run("tc_pixel_assembly") then
                info("Two bytes assembled into correct RGB565 word");
                do_reset(rst_n, i2c_done, vsync, href);
                i2c_done <= '1';
                -- Drive VSYNC
                vsync <= '1'; pclk_wait(6);
                vsync <= '0';
                -- Drive one pixel: byte0=0xF8, byte1=0x1F
                -- Expected pixel = 0xF81F
                href     <= '1';
                cam_data <= x"F8";
                wait until rising_edge(pclk);
                cam_data <= x"1F";
                wait until rising_edge(pclk);
                href     <= '0';
                pclk_wait(4);
                check_equal(fifo_wr_data,
                    std_logic_vector'(x"F81F"),
                    "RGB565 assembly: 0xF8,0x1F -> 0xF81F");

            -- -----------------------------------------------------------------
            elsif run("tc_byte_order") then
                info("Byte 0 = high byte [15:8], Byte 1 = low byte [7:0]");
                do_reset(rst_n, i2c_done, vsync, href);
                i2c_done <= '1';
                vsync <= '1'; pclk_wait(6); vsync <= '0';
                -- Pixel: byte0=0xAB (high), byte1=0xCD (low)
                href     <= '1';
                cam_data <= x"AB";
                wait until rising_edge(pclk);
                cam_data <= x"CD";
                wait until rising_edge(pclk);
                href     <= '0';
                pclk_wait(4);
                check_equal(fifo_wr_data(15 downto 8),
                    std_logic_vector'(x"AB"), "High byte = first byte");
                check_equal(fifo_wr_data(7 downto 0),
                    std_logic_vector'(x"CD"), "Low byte = second byte");

            -- -----------------------------------------------------------------
            elsif run("tc_href_alignment") then
                info("byte_sel resets on falling HREF (line boundary alignment)");
                do_reset(rst_n, i2c_done, vsync, href);
                i2c_done <= '1';
                vsync <= '1'; pclk_wait(6); vsync <= '0';
                -- Drive 1.5 pixels (3 bytes — misaligned on purpose)
                -- Then drop HREF — byte_sel must reset
                -- Next line starts fresh with byte0
                href     <= '1';
                cam_data <= x"11"; wait until rising_edge(pclk);
                cam_data <= x"22"; wait until rising_edge(pclk);  -- pixel 1 done
                cam_data <= x"33"; wait until rising_edge(pclk);  -- orphan byte
                href     <= '0';                                    -- HREF falls mid-pixel
                pclk_wait(4);
                -- Decimation mode captures only even lines; advance one line so
                -- the checked pixel lands on an even line.
                href     <= '1';
                cam_data <= x"00";
                wait until rising_edge(pclk);
                href     <= '0';
                pclk_wait(2);
                pix_before := wr_en_count;
                -- Next line: first byte on new href should be treated as byte0
                href     <= '1';
                cam_data <= x"AA"; wait until rising_edge(pclk);  -- byte0 of new pixel
                cam_data <= x"BB"; wait until rising_edge(pclk);  -- byte1 -> write
                href     <= '0';
                pclk_wait(4);
                pix_after := wr_en_count;
                check_equal(pix_after - pix_before, 1,
                    "Exactly 1 clean pixel after HREF re-alignment");
                check_equal(fifo_wr_data,
                    std_logic_vector'(x"AABB"),
                    "Aligned pixel = 0xAABB after HREF reset");

            -- -----------------------------------------------------------------
            elsif run("tc_fifo_full_drop") then
                info("wr_en=0 when FIFO full, byte_sel still advances");
                do_reset(rst_n, i2c_done, vsync, href);
                i2c_done  <= '1';
                fifo_full <= '1';   -- FIFO full!
                vsync <= '1'; pclk_wait(6); vsync <= '0';
                -- Drive two pixel pairs
                href     <= '1';
                cam_data <= x"DE"; wait until rising_edge(pclk);
                cam_data <= x"AD"; wait until rising_edge(pclk);
                cam_data <= x"BE"; wait until rising_edge(pclk);
                cam_data <= x"EF"; wait until rising_edge(pclk);
                href     <= '0';
                pclk_wait(4);
                check_equal(wr_en_count, 0,
                    "wr_en must be 0 when FIFO full");
                -- Now clear FIFO full and verify next pixel is written
                fifo_full <= '0';
                -- Advance one dummy line so the next pixel lands on an even line
                href     <= '1';
                cam_data <= x"00";
                wait until rising_edge(pclk);
                href     <= '0';
                pclk_wait(2);
                href     <= '1';
                cam_data <= x"12"; wait until rising_edge(pclk);
                cam_data <= x"34"; wait until rising_edge(pclk);
                href     <= '0';
                pclk_wait(4);
                check_equal(wr_en_count, 1,
                    "wr_en asserts once FIFO is no longer full");

            -- -----------------------------------------------------------------
            elsif run("tc_frame_done_pulse") then
                info("frame_done asserts when VSYNC rises during S_CAPTURE");
                do_reset(rst_n, i2c_done, vsync, href);
                i2c_done <= '1';
                -- First frame start
                vsync <= '1'; pclk_wait(6); vsync <= '0';
                -- Drive a few pixels
                href     <= '1';
                cam_data <= x"AA"; wait until rising_edge(pclk);
                cam_data <= x"BB"; wait until rising_edge(pclk);
                href     <= '0';
                pclk_wait(4);
                -- End frame: VSYNC rises
                vsync <= '1';
                wait until frame_done = '1' for 10 us;
                check_equal(frame_done, '1',
                    "frame_done must assert on VSYNC rising in S_CAPTURE");

            -- -----------------------------------------------------------------
            elsif run("tc_frame_done_width") then
                info("frame_done held for >= 2 PCLK cycles");
                do_reset(rst_n, i2c_done, vsync, href);
                i2c_done <= '1';
                vsync <= '1'; pclk_wait(6); vsync <= '0';
                href     <= '1';
                cam_data <= x"AA"; wait until rising_edge(pclk);
                cam_data <= x"BB"; wait until rising_edge(pclk);
                href     <= '0'; pclk_wait(2);
                -- Trigger end of frame
                vsync <= '1';
                -- Count how many cycles frame_done stays high
                fd_cycles := 0;
                for i in 0 to 5 loop
                    wait until rising_edge(pclk);
                    if frame_done = '1' then
                        fd_cycles := fd_cycles + 1;
                    end if;
                end loop;
                check(fd_cycles >= 2,
                    "frame_done must be high for >= 2 cycles, got " &
                    integer'image(fd_cycles));

            -- -----------------------------------------------------------------
            elsif run("tc_multi_frame") then
                info("Two consecutive frames captured without missed pixels");
                do_reset(rst_n, i2c_done, vsync, href);
                i2c_done <= '1';
                -- Frame 1: 4 lines x 4 pixels
                drive_frame(vsync, href, cam_data, 4, 4, 0);
                pix_before := wr_en_count;
                -- Frame 2: 4 lines x 4 pixels
                vsync <= '0'; pclk_wait(4);
                drive_frame(vsync, href, cam_data, 4, 4, 128);
                pix_after := wr_en_count;
                check_equal(pix_before, 4,
                    "Frame 1: expected 4 pixels written");
                check_equal(pix_after - pix_before, 4,
                    "Frame 2: expected 4 more pixels written");

            -- -----------------------------------------------------------------
            elsif run("tc_full_line") then
                info("Decimation: 640 pixels per line produces 320 wr_en pulses");
                do_reset(rst_n, i2c_done, vsync, href);
                i2c_done <= '1';
                vsync <= '1'; pclk_wait(20); vsync <= '0';
                pix_before := wr_en_count;
                drive_line(href, cam_data, H_PIXELS, 0, H_BLANK);
                pix_after := wr_en_count;
                check_equal(pix_after - pix_before, H_PIXELS/2,
                    "640 pixels per line");

            end if;
        end loop;

        test_runner_cleanup(runner);
    end process;

    test_runner_watchdog(runner, 30 ms);

end architecture sim;
