-- =============================================================================
-- camera_subsystem.vhd  (CORRECTED)
-- Camera capture subsystem wrapper
--
-- Contains:
--   u_i2c  : i2c_top          -- SCCB master, programs OV7670 on startup
--   u_cam  : camera_interface -- pixel capture FSM (PCLK domain)
--   u_fifo : asyn_fifo        -- CDC bridge: PCLK write -> clk_130m (100MHz) read
--
-- Fixes applied:
--   1. i2c_done_int now wired to camera_interface i2c_done port
--      (camera_interface will not capture until SCCB config is complete)
--   2. i2c_top clock corrected: uses clk_24m (consistent with HALF_PERIOD=120)
--   3. Component declaration for camera_interface updated with i2c_done port
--   4. frame_done held for 2 PCLK cycles by camera_interface — safe for 2-FF
--      re-synchronisation in sdram_subsystem
--
    -- Clock domains:
    --   clk_24m  : i2c_top (SCCB master), cam_xclk output
    --   cam_pclk : camera_interface + asyn_fifo write side
    --   clk_130m : asyn_fifo read side (100MHz) -> sdram_subsystem
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity camera_subsystem is
    generic (
        USE_VENDOR_FIFO : boolean := false
    );
    port (
        -- Clocks & reset
        clk_24m      : in    std_logic;   -- 24 MHz PLL output (XCLK + SCCB)
        clk_130m     : in    std_logic;   -- 100 MHz (FIFO read side)
        rst_n        : in    std_logic;
        invert_sync  : in    std_logic;   -- tie to SW(1): '1' if VSYNC/HREF polarity wrong
        sample_falling : in  std_logic;   -- tie to SW(2): '1' = capture on falling edge
        reverse_bits : in    std_logic;   -- tie to SW(6): reverse D[7:0] bit order for debug
        data_map_sel : in    std_logic_vector(1 downto 0); -- tie to SW(9 downto 8): extra D[7:0] remap modes
        swap_bytes   : in    std_logic;   -- tie to SW(7): swap RGB565 byte order for debug

        -- OV7670 physical pins (connect to GPIO_0 header)
        cam_pclk     : in    std_logic;   -- pixel clock from OV7670
        cam_vsync    : in    std_logic;   -- frame sync (active high)
        cam_href     : in    std_logic;   -- line valid  (active high)
        cam_d        : in    std_logic_vector(7 downto 0);
        cam_xclk     : out   std_logic;   -- master clock to OV7670
        cam_sioc     : out   std_logic;   -- SCCB clock
        cam_siod     : inout std_logic;   -- SCCB data
        cam_rst_n    : out   std_logic;   -- OV7670 RESETB (active low)
        cam_pwdn     : out   std_logic;   -- OV7670 PWDN   ('0' = on)

        -- FIFO read interface (100 MHz domain -> sdram_subsystem)
        fifo_rd_en    : in    std_logic;
        fifo_rd_data  : out   std_logic_vector(15 downto 0);
        fifo_empty    : out   std_logic;
        fifo_rd_usedw : out   std_logic_vector(8 downto 0);  -- DEPTH_LOG2=9

        -- End-of-frame pulse (PCLK domain, 2 cycles wide)
        -- Must be re-synchronised by sdram_subsystem before use
        frame_done   : out   std_logic;

        -- Debug / status
        i2c_done       : out   std_logic;
        pclk_heartbeat : out   std_logic;
        fifo_wr_pulse  : out   std_logic;
        last_line_count      : out std_logic_vector(9 downto 0);
        last_pixel_count_div : out std_logic_vector(8 downto 0);
        frame_valid_dbg      : out std_logic;
        raw_byte_dbg         : out std_logic_vector(7 downto 0);
        mapped_byte_dbg      : out std_logic_vector(7 downto 0);
        pixel_word_dbg       : out std_logic_vector(15 downto 0);
        ref_pixels01_dbg     : out std_logic_vector(31 downto 0);
        ref_pixels23_dbg     : out std_logic_vector(31 downto 0);
        ref_pixels45_dbg     : out std_logic_vector(31 downto 0);
        ref_pixels67_dbg     : out std_logic_vector(31 downto 0);
        line0_pair_dbg       : out   std_logic_vector(31 downto 0);
        line60_pair_dbg      : out   std_logic_vector(31 downto 0);
        line120_pair_dbg     : out   std_logic_vector(31 downto 0);
        line180_pair_dbg     : out   std_logic_vector(31 downto 0);
        reg_cfg0_dbg         : out std_logic_vector(31 downto 0);
        reg_cfg1_dbg         : out std_logic_vector(31 downto 0);
        reg_cfg2_dbg         : out std_logic_vector(31 downto 0);
        reg_cfg3_dbg         : out std_logic_vector(31 downto 0)
    );
end entity camera_subsystem;

architecture rtl of camera_subsystem is

    -- =========================================================================
    -- Component declarations
    -- =========================================================================

    component i2c_top
        port (
            clk       : in    std_logic;
            rst_n     : in    std_logic;
            sioc      : out   std_logic;
            siod      : inout std_logic;
            done      : out   std_logic;
            cam_rst_n : out   std_logic;
            cam_pwdn  : out   std_logic;
            reg_cfg0_dbg : out std_logic_vector(31 downto 0);
            reg_cfg1_dbg : out std_logic_vector(31 downto 0);
            reg_cfg2_dbg : out std_logic_vector(31 downto 0);
            reg_cfg3_dbg : out std_logic_vector(31 downto 0)
        );
    end component;

    component camera_interface
        port (
            clk            : in  std_logic;
            pclk           : in  std_logic;
            rst_n          : in  std_logic;
            i2c_done       : in  std_logic;
            invert_sync    : in  std_logic;
            sample_falling : in  std_logic;
            reverse_bits   : in  std_logic;
            data_map_sel   : in  std_logic_vector(1 downto 0);
            swap_bytes     : in  std_logic;
            vsync          : in  std_logic;
            href           : in  std_logic;
            cam_data       : in  std_logic_vector(7 downto 0);
            fifo_wr_en     : out std_logic;
            fifo_wr_data   : out std_logic_vector(15 downto 0);
            fifo_full      : in  std_logic;
            frame_done     : out std_logic;
            pclk_heartbeat : out std_logic;
            last_line_count      : out std_logic_vector(9 downto 0);
            last_pixel_count_div : out std_logic_vector(8 downto 0);
            frame_valid_dbg      : out std_logic;
            raw_byte_dbg         : out std_logic_vector(7 downto 0);
            mapped_byte_dbg      : out std_logic_vector(7 downto 0);
            pixel_word_dbg       : out std_logic_vector(15 downto 0);
            ref_pixels01_dbg     : out std_logic_vector(31 downto 0);
            ref_pixels23_dbg     : out std_logic_vector(31 downto 0);
            ref_pixels45_dbg     : out std_logic_vector(31 downto 0);
            ref_pixels67_dbg     : out std_logic_vector(31 downto 0);
            line0_pair_dbg       : out std_logic_vector(31 downto 0);
            line60_pair_dbg      : out std_logic_vector(31 downto 0);
            line120_pair_dbg     : out std_logic_vector(31 downto 0);
            line180_pair_dbg     : out std_logic_vector(31 downto 0)
        );
    end component;

    component asyn_fifo
        generic (
            DATA_WIDTH : integer;
            DEPTH_LOG2 : integer;
            USE_DCFIFO : boolean
        );
        port (
            wr_clk   : in  std_logic;
            wr_rst_n : in  std_logic;
            wr_en    : in  std_logic;
            wr_data  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            wr_full  : out std_logic;
            rd_clk   : in  std_logic;
            rd_rst_n : in  std_logic;
            rd_en    : in  std_logic;
            rd_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
            rd_empty : out std_logic;
            rd_usedw : out std_logic_vector(DEPTH_LOG2-1 downto 0)
        );
    end component;

    -- =========================================================================
    -- Internal signals
    -- =========================================================================

    -- i2c_top -> camera_interface (KEY FIX: was not connected before)
    signal i2c_done_int  : std_logic := '0';

    -- camera_interface -> asyn_fifo (camera PCLK domain)
    signal fifo_wr_en_int  : std_logic;
    signal fifo_wr_data_int: std_logic_vector(15 downto 0);
    signal fifo_full_int   : std_logic;

begin

    -- =========================================================================
    -- XCLK: feed 24 MHz PLL clock directly to OV7670 as master clock
    -- OV7670 uses this to generate its own PCLK output
    -- =========================================================================
    cam_xclk <= clk_24m;
    i2c_done <= i2c_done_int;
    fifo_wr_pulse <= fifo_wr_en_int;

    -- =========================================================================
    -- u_i2c: SCCB master
    -- Programs all OV7670 registers on startup.
    -- Holds cam_rst_n low for 5ms, then releases and begins SCCB writes.
    -- Asserts i2c_done_int when all registers are written.
    -- =========================================================================
    u_i2c : i2c_top
        port map (
            clk       => clk_24m,        -- 24 MHz, HALF_PERIOD=120 -> 100kHz
            rst_n     => rst_n,
            sioc      => cam_sioc,
            siod      => cam_siod,
            done      => i2c_done_int,
            cam_rst_n => cam_rst_n,
            cam_pwdn  => cam_pwdn,
            reg_cfg0_dbg => reg_cfg0_dbg,
            reg_cfg1_dbg => reg_cfg1_dbg,
            reg_cfg2_dbg => reg_cfg2_dbg,
            reg_cfg3_dbg => reg_cfg3_dbg
        );

    -- =========================================================================
    -- u_cam: pixel capture FSM
    -- Runs on OV7670 PCLK.
    -- Will not begin capturing until i2c_done_int = '1'.
    -- =========================================================================
    u_cam : camera_interface
        port map (
            clk            => clk_130m,
            pclk           => cam_pclk,
            rst_n          => rst_n,
            i2c_done       => i2c_done_int,
            invert_sync    => invert_sync,
            sample_falling => sample_falling,
            reverse_bits   => reverse_bits,
            data_map_sel   => data_map_sel,
            swap_bytes     => swap_bytes,
            vsync          => cam_vsync,
            href           => cam_href,
            cam_data       => cam_d,
            fifo_wr_en     => fifo_wr_en_int,
            fifo_wr_data   => fifo_wr_data_int,
            fifo_full      => fifo_full_int,
            frame_done     => frame_done,
            pclk_heartbeat => pclk_heartbeat,
            last_line_count      => last_line_count,
            last_pixel_count_div => last_pixel_count_div,
            frame_valid_dbg      => frame_valid_dbg,
            raw_byte_dbg         => raw_byte_dbg,
            mapped_byte_dbg      => mapped_byte_dbg,
            pixel_word_dbg       => pixel_word_dbg,
            ref_pixels01_dbg     => ref_pixels01_dbg,
            ref_pixels23_dbg     => ref_pixels23_dbg,
            ref_pixels45_dbg     => ref_pixels45_dbg,
            ref_pixels67_dbg     => ref_pixels67_dbg,
            line0_pair_dbg       => line0_pair_dbg,
            line60_pair_dbg      => line60_pair_dbg,
            line120_pair_dbg     => line120_pair_dbg,
            line180_pair_dbg     => line180_pair_dbg
        );

    u_fifo : asyn_fifo
        generic map (
            DATA_WIDTH => 16,
            DEPTH_LOG2 => 9,
            USE_DCFIFO => USE_VENDOR_FIFO
        )
        port map (
            wr_clk   => cam_pclk,
            wr_rst_n => rst_n,
            wr_en    => fifo_wr_en_int,
            wr_data  => fifo_wr_data_int,
            wr_full  => fifo_full_int,
            rd_clk   => clk_130m,
            rd_rst_n => rst_n,
            rd_en    => fifo_rd_en,
            rd_data  => fifo_rd_data,
            rd_empty => fifo_empty,
            rd_usedw => fifo_rd_usedw
        );

end architecture rtl;
