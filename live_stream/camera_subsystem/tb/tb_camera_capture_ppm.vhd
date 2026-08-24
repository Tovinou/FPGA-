library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;
use std.env.all;

entity tb_camera_capture_ppm is
end entity;

architecture sim of tb_camera_capture_ppm is
    constant T_24M  : time := 41667 ps;
    constant T_PCLK : time := 41667 ps;
    constant T_100M : time := 10 ns;

    constant IMG_W  : integer := 64;
    constant IMG_H  : integer := 48;
    constant H_BLANK_CY : integer := 20;

    signal clk_24m  : std_logic := '0';
    signal clk_100m : std_logic := '0';
    signal cam_pclk : std_logic := '0';
    signal rst_n    : std_logic := '0';

    signal cam_vsync : std_logic := '0';
    signal cam_href  : std_logic := '0';
    signal cam_d     : std_logic_vector(7 downto 0) := (others => '0');

    signal cam_xclk  : std_logic;
    signal cam_sioc  : std_logic;
    signal cam_siod  : std_logic := 'H';
    signal cam_rst_n : std_logic;
    signal cam_pwdn  : std_logic;

    signal fifo_rd_en   : std_logic := '0';
    signal fifo_rd_data : std_logic_vector(15 downto 0);
    signal fifo_empty   : std_logic;
    signal frame_done   : std_logic;
    signal i2c_done     : std_logic;

    function rgb565_from_xy(x, y : integer) return std_logic_vector is
        variable r5 : integer;
        variable g6 : integer;
        variable b5 : integer;
    begin
        r5 := (x * 31) / (IMG_W - 1);
        g6 := (y * 63) / (IMG_H - 1);
        b5 := 31 - r5;
        return std_logic_vector(to_unsigned(r5, 5) & to_unsigned(g6, 6) & to_unsigned(b5, 5));
    end function;

    procedure pclk_wait(n : natural) is
    begin
        for i in 1 to n loop
            wait until rising_edge(cam_pclk);
        end loop;
    end procedure;

    procedure clk130_wait(n : natural) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk_100m);
        end loop;
    end procedure;

    procedure drive_frame_rgb565(
        signal cam_vsync : out std_logic;
        signal cam_href  : out std_logic;
        signal cam_d     : out std_logic_vector(7 downto 0)
    ) is
        variable pix : std_logic_vector(15 downto 0);
    begin
        cam_vsync <= '1';
        pclk_wait(10);
        cam_vsync <= '0';

        for y in 0 to IMG_H - 1 loop
            cam_href <= '1';
            for x in 0 to IMG_W - 1 loop
                pix := rgb565_from_xy(x, y);
                cam_d <= pix(15 downto 8);
                wait until rising_edge(cam_pclk);
                cam_d <= pix(7 downto 0);
                wait until rising_edge(cam_pclk);
            end loop;
            cam_href <= '0';
            cam_d <= (others => '0');
            pclk_wait(H_BLANK_CY);
        end loop;
    end procedure;

    procedure write_ppm_from_fifo(
        signal fifo_rd_en   : out std_logic;
        signal fifo_rd_data : in  std_logic_vector(15 downto 0);
        signal fifo_empty   : in  std_logic
    ) is
        file f : text;
        variable l : line;
        variable pix : std_logic_vector(15 downto 0);
        variable r5 : integer;
        variable g6 : integer;
        variable b5 : integer;
        variable r8 : integer;
        variable g8 : integer;
        variable b8 : integer;
    begin
        file_open(f, "camera_capture.ppm", write_mode);
        write(l, string'("P3"));
        writeline(f, l);
        write(l, integer'image(IMG_W) & " " & integer'image(IMG_H));
        writeline(f, l);
        write(l, string'("255"));
        writeline(f, l);

        wait until fifo_empty = '0' for 2 ms;

        for y in 0 to IMG_H - 1 loop
            for x in 0 to IMG_W - 1 loop
                fifo_rd_en <= '1';
                wait until rising_edge(clk_100m);
                pix := fifo_rd_data;
                fifo_rd_en <= '0';
                wait until rising_edge(clk_100m);

                r5 := to_integer(unsigned(pix(15 downto 11)));
                g6 := to_integer(unsigned(pix(10 downto 5)));
                b5 := to_integer(unsigned(pix(4 downto 0)));

                r8 := (r5 * 255) / 31;
                g8 := (g6 * 255) / 63;
                b8 := (b5 * 255) / 31;

                write(l, integer'image(r8) & " " & integer'image(g8) & " " & integer'image(b8));
                writeline(f, l);
            end loop;
        end loop;

        file_close(f);
    end procedure;

begin
    clk_24m  <= not clk_24m  after T_24M / 2;
    clk_100m <= not clk_100m after T_100M / 2;
    cam_pclk <= not cam_pclk after T_PCLK / 2;

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
            frame_done   => frame_done,
            i2c_done     => i2c_done
        );

    main : process
    begin
        rst_n <= '0';
        pclk_wait(20);
        clk130_wait(20);
        rst_n <= '1';

        wait until i2c_done = '1' for 60 ms;
        if i2c_done /= '1' then
            assert false severity failure;
        end if;

        drive_frame_rgb565(cam_vsync, cam_href, cam_d);
        clk130_wait(50);
        write_ppm_from_fifo(fifo_rd_en, fifo_rd_data, fifo_empty);
        stop;
        wait;
    end process;
end architecture;
