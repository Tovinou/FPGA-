-- =============================================================================
-- Komlan Tovinou
-- 2026-04-01
--
-- stream_top.vhd
-- Top-level entity: OV7670 -> SDRAM -> VGA real-time streaming
-- Target: Intel MAX10 DE10-Lite (10M50DAF484C7G)
--
-- This file contains NO logic — only component instantiation and port wiring.
-- All logic lives in the five subsystems below.
--
-- Hierarchy:
--   stream_top
--   ├── pll_main          (altpll_core.qip)
--   ├── sys_ctrl          (debounce_explicit)
--   ├── camera_subsystem  (i2c_top, camera_interface, asyn_fifo)
--   ├── sdram_subsystem   (sdram_interface, sdram_controller)
--   └── vga_subsystem     (asyn_fifo, vga_core, vga_interface)
--
-- Clock domains:
--   PCLK    25 MHz   OV7670-generated, fed back into camera_subsystem
--   
--   clk_100m 75MHz   PLL c0, drives sdram_subsystem + SDRAM clock pin
--   DRAM_CLK 75MHz   PLL c1 (phase-shifted), goes directly to SDRAM pin
--   clk_25m 25 MHz   PLL c2, drives vga_subsystem and drives i2c_top + XCLK output
--   locked
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity stream_top is
    port (
        MAX10_CLK1_50  : in    std_logic;    -- DE10-Lite 50 MHz oscillator
        KEY            : in    std_logic_vector(1 downto 0); -- Push buttons (active low)
        LEDR           : out   std_logic_vector(9 downto 0); -- LEDs (debug)
        SW             : in    std_logic_vector(9 downto 0); -- Switches

        -- OV7670 camera (GPIO_0 header)
        OV7670_PCLK    : in    std_logic;
        OV7670_HREF    : in    std_logic;
        OV7670_VSYNC   : in    std_logic;
        OV7670_D       : in    std_logic_vector(7 downto 0);
        OV7670_XCLK    : out   std_logic;
        OV7670_SIOC    : out   std_logic;
        OV7670_SIOD    : inout std_logic;
        OV7670_RESET_N : out   std_logic;
        OV7670_PWDN    : out   std_logic;

        -- SDRAM IS42S16320F
        DRAM_CLK       : out   std_logic;
        DRAM_CKE       : out   std_logic;
        DRAM_CS_N      : out   std_logic;
        DRAM_RAS_N     : out   std_logic;
        DRAM_CAS_N     : out   std_logic;
        DRAM_WE_N      : out   std_logic;
        DRAM_BA        : out   std_logic_vector(1 downto 0);
        DRAM_ADDR      : out   std_logic_vector(12 downto 0);
        DRAM_UDQM      : out   std_logic;
        DRAM_LDQM      : out   std_logic;
        DRAM_DQ        : inout std_logic_vector(15 downto 0);

        -- VGA connector
        VGA_R          : out   std_logic_vector(3 downto 0);
        VGA_G          : out   std_logic_vector(3 downto 0);
        VGA_B          : out   std_logic_vector(3 downto 0);
        VGA_HS         : out   std_logic;
        VGA_VS         : out   std_logic
    );
end entity stream_top;

architecture rtl of stream_top is

    -- =========================================================================
    -- Component declarations
    -- =========================================================================

    component pll_main
        port (
            inclk0  : in  std_logic;
            c0      : out std_logic;
            c1      : out std_logic;
            c2      : out std_logic;
            locked  : out std_logic
        );
    end component;

    component sys_ctrl
        port (
            clk_50m    : in  std_logic;
            pll_locked : in  std_logic;
            key0       : in  std_logic;
            rst_n      : out std_logic;
            locked_led : out std_logic
        );
    end component;

    -- In-System Sources and Probes for remote debugging
    component altsource_probe
        generic (
            sld_auto_instance_index : string := "YES";
            sld_instance_index      : integer := 0;
            source_initial_value    : string := "0";
            source_width            : integer := 1;
            probe_width             : integer := 1;
            instance_id             : string := "NONE"
        );
        port (
            source : out std_logic_vector(source_width-1 downto 0);
            probe  : in  std_logic_vector(probe_width-1 downto 0)
        );
    end component;

    component camera_subsystem
        generic (
            USE_VENDOR_FIFO : boolean := false
        );
        port (
            clk_24m      : in    std_logic;
            clk_130m     : in    std_logic;
            rst_n        : in    std_logic;
            invert_sync  : in    std_logic;
            sample_falling : in  std_logic;
            reverse_bits : in    std_logic;
            data_map_sel : in    std_logic_vector(1 downto 0);
            swap_bytes   : in    std_logic;
            cam_pclk     : in    std_logic;
            cam_vsync    : in    std_logic;
            cam_href     : in    std_logic;
            cam_d        : in    std_logic_vector(7 downto 0);
            cam_xclk     : out   std_logic;
            cam_sioc     : out   std_logic;
            cam_siod     : inout std_logic;
            cam_rst_n    : out   std_logic;
            cam_pwdn     : out   std_logic;
            fifo_rd_en   : in    std_logic;
            fifo_rd_data : out   std_logic_vector(15 downto 0);
            fifo_empty   : out   std_logic;
            fifo_rd_usedw: out   std_logic_vector(8 downto 0);  -- DEPTH_LOG2=9
            frame_done     : out   std_logic;
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
            line0_pair_dbg       : out std_logic_vector(31 downto 0);
            line60_pair_dbg      : out std_logic_vector(31 downto 0);
            line120_pair_dbg     : out std_logic_vector(31 downto 0);
            line180_pair_dbg     : out std_logic_vector(31 downto 0);
            reg_cfg0_dbg         : out std_logic_vector(31 downto 0);
            reg_cfg1_dbg         : out std_logic_vector(31 downto 0);
            reg_cfg2_dbg         : out std_logic_vector(31 downto 0);
            reg_cfg3_dbg         : out std_logic_vector(31 downto 0)
        );
    end component;

    component sdram_subsystem
        port (
            clk_130m         : in    std_logic;
            rst_n            : in    std_logic;
            test_mode        : out   std_logic_vector(1 downto 0);
            test_leds        : out   std_logic_vector(9 downto 0);
            bist_release_n   : in    std_logic;
            cam_fifo_rd_en   : out   std_logic;
            cam_fifo_rd_data : in    std_logic_vector(15 downto 0);
            cam_fifo_empty   : in    std_logic;
            cam_fifo_rd_usedw: in    std_logic_vector(8 downto 0);  -- DEPTH_LOG2=9
            frame_done_async : in    std_logic;
            vga_vsync_async  : in    std_logic;
            vga_fifo_wr_en   : out   std_logic;
            vga_fifo_wr_data : out   std_logic_vector(15 downto 0);
            vga_fifo_full    : in    std_logic;
            debug_cfr01_dbg  : out   std_logic_vector(31 downto 0);
            debug_cfr23_dbg  : out   std_logic_vector(31 downto 0);
            debug_cfr45_dbg  : out   std_logic_vector(31 downto 0);
            debug_cfr67_dbg  : out   std_logic_vector(31 downto 0);
            debug_vgr01_dbg  : out   std_logic_vector(31 downto 0);
            debug_vgr23_dbg  : out   std_logic_vector(31 downto 0);
            debug_vgr45_dbg  : out   std_logic_vector(31 downto 0);
            debug_vgr67_dbg  : out   std_logic_vector(31 downto 0);
            debug_vgl0_dbg   : out   std_logic_vector(31 downto 0);
            debug_vgl60_dbg  : out   std_logic_vector(31 downto 0);
            debug_vgl120_dbg : out   std_logic_vector(31 downto 0);
            debug_vgl180_dbg : out   std_logic_vector(31 downto 0);
            debug_sch_dbg    : out   std_logic_vector(31 downto 0);
            sdram_cke        : out   std_logic;
            sdram_cs_n       : out   std_logic;
            sdram_ras_n      : out   std_logic;
            sdram_cas_n      : out   std_logic;
            sdram_we_n       : out   std_logic;
            sdram_ba         : out   std_logic_vector(1 downto 0);
            sdram_addr       : out   std_logic_vector(12 downto 0);
            sdram_dqm        : out   std_logic_vector(1 downto 0);
            sdram_dq         : inout std_logic_vector(15 downto 0)
        );
    end component;

    component vga_subsystem
        generic (
            USE_VENDOR_FIFO : boolean := false
        );
        port (
            clk_25m      : in  std_logic;
            clk_130m     : in  std_logic;
            rst_n        : in  std_logic;
            test_mode    : in  std_logic_vector(1 downto 0);
            fifo_wr_en   : in  std_logic;
            fifo_wr_data : in  std_logic_vector(15 downto 0);
            fifo_full    : out std_logic;
            vga_r        : out std_logic_vector(3 downto 0);
            vga_g        : out std_logic_vector(3 downto 0);
            vga_b        : out std_logic_vector(3 downto 0);
            vga_hs       : out std_logic;
            vga_vs       : out std_logic;
            fifo_rd_en_dbg   : out std_logic;
            fifo_empty_dbg   : out std_logic;
            fifo_usedw_dbg   : out std_logic_vector(11 downto 0);
            h_count_dbg      : out std_logic_vector(9 downto 0);
            v_count_dbg      : out std_logic_vector(9 downto 0);
            out_pixels01_dbg  : out std_logic_vector(31 downto 0);
            out_pixels23_dbg  : out std_logic_vector(31 downto 0);
            out_pixels45_dbg  : out std_logic_vector(31 downto 0);
            out_pixels67_dbg  : out std_logic_vector(31 downto 0);
            read_pixels01_dbg : out std_logic_vector(31 downto 0);
            read_pixels23_dbg : out std_logic_vector(31 downto 0);
            read_pixels45_dbg : out std_logic_vector(31 downto 0);
            read_pixels67_dbg : out std_logic_vector(31 downto 0);
            read_line0_pair_dbg   : out std_logic_vector(31 downto 0);
            read_line60_pair_dbg  : out std_logic_vector(31 downto 0);
            read_line120_pair_dbg : out std_logic_vector(31 downto 0);
            read_line180_pair_dbg : out std_logic_vector(31 downto 0);
            underflow_count_dbg : out std_logic_vector(31 downto 0);
            out_line0_pair_dbg   : out std_logic_vector(31 downto 0);
            out_line60_pair_dbg  : out std_logic_vector(31 downto 0);
            out_line120_pair_dbg : out std_logic_vector(31 downto 0);
            out_line180_pair_dbg : out std_logic_vector(31 downto 0)
        );
    end component;

    -- =========================================================================
    -- Internal signals
    -- =========================================================================

    -- Clocks from PLL
    signal clk_25m       : std_logic;
    signal clk_100m      : std_logic;
    signal clk_50m       : std_logic;
    signal clk_dram      : std_logic;
    signal pll_locked    : std_logic;

    signal ov7670_xclk_cnt : unsigned(2 downto 0) := (others => '0');
    signal ov7670_xclk_sel : std_logic_vector(1 downto 0);
    signal ov7670_xclk_out : std_logic;

    -- Global reset
    signal rst_n         : std_logic;

    -- camera_subsystem <-> sdram_subsystem
    signal cam_fifo_rd_en_sdram   : std_logic;
    signal cam_fifo_rd_data : std_logic_vector(15 downto 0);
    signal cam_fifo_empty   : std_logic;
    signal cam_fifo_rd_usedw: std_logic_vector(8 downto 0);
    signal frame_done       : std_logic;

    -- sdram_subsystem <-> vga_subsystem
    signal vga_fifo_wr_en_sdram   : std_logic;
    signal vga_fifo_wr_data_sdram : std_logic_vector(15 downto 0);
    signal vga_fifo_full    : std_logic;
    signal vga_vs_int       : std_logic;

    -- SDRAM DQM
    signal sdram_dqm        : std_logic_vector(1 downto 0);

    -- Debug
    signal i2c_done         : std_logic;
    signal sdram_test_mode  : std_logic_vector(1 downto 0);
    signal vga_test_mode    : std_logic_vector(1 downto 0);
    signal sdram_test_leds  : std_logic_vector(9 downto 0);
    signal pclk_sync1       : std_logic;
    signal pclk_sync2       : std_logic;
    signal vsync_sync1      : std_logic;
    signal vsync_sync2      : std_logic;
    signal href_sync1       : std_logic;
    signal href_sync2       : std_logic;
    signal pclk_prev        : std_logic;
    signal vsync_prev       : std_logic;
    signal href_prev        : std_logic;
    signal pclk_edges       : unsigned(23 downto 0);
    signal vsync_edges      : unsigned(7 downto 0);
    signal href_edges       : unsigned(15 downto 0);
    signal cam_pclk_heartbeat: std_logic;
    signal win_cnt          : unsigned(24 downto 0);
    signal pclk_present     : std_logic;
    signal vsync_present    : std_logic;
    signal href_present     : std_logic; -- DEBUG: Raw camera signal monitor
    
    signal frame_done_stretch: std_logic := '0';
    signal frame_valid_stretch: std_logic := '0';
    signal stretch_cnt      : unsigned(23 downto 0) := (others => '0');
    signal valid_stretch_cnt: unsigned(23 downto 0) := (others => '0');
    signal frame_done_s1    : std_logic := '0';
    signal frame_done_s2    : std_logic := '0';
    signal frame_valid_s1   : std_logic := '0';
    signal frame_valid_s2   : std_logic := '0';
    signal cam_fifo_has_data: std_logic;
    signal cam_fifo_wr_pulse: std_logic;
    signal cam_last_line_count      : std_logic_vector(9 downto 0);
    signal cam_last_pixel_count_div : std_logic_vector(8 downto 0);
    signal cam_frame_valid_dbg      : std_logic;
    signal cam_raw_byte_dbg         : std_logic_vector(7 downto 0);
    signal cam_mapped_byte_dbg      : std_logic_vector(7 downto 0);
    signal cam_pixel_word_dbg       : std_logic_vector(15 downto 0);
    signal cam_ref_pixels01_dbg     : std_logic_vector(31 downto 0);
    signal cam_ref_pixels23_dbg     : std_logic_vector(31 downto 0);
    signal cam_ref_pixels45_dbg     : std_logic_vector(31 downto 0);
    signal cam_ref_pixels67_dbg     : std_logic_vector(31 downto 0);
    signal cam_line0_pair_dbg       : std_logic_vector(31 downto 0);
    signal cam_line60_pair_dbg      : std_logic_vector(31 downto 0);
    signal cam_line120_pair_dbg     : std_logic_vector(31 downto 0);
    signal cam_line180_pair_dbg     : std_logic_vector(31 downto 0);
    signal cam_reg_cfg0_dbg         : std_logic_vector(31 downto 0);
    signal cam_reg_cfg1_dbg         : std_logic_vector(31 downto 0);
    signal cam_reg_cfg2_dbg         : std_logic_vector(31 downto 0);
    signal cam_reg_cfg3_dbg         : std_logic_vector(31 downto 0);
    signal cam_wr_stretch   : std_logic := '0';
    signal cam_wr_cnt       : unsigned(23 downto 0) := (others => '0');
    signal cam_wr_edge_cnt  : unsigned(23 downto 0) := (others => '0');
    signal cam_wr_win_cnt   : unsigned(23 downto 0) := (others => '0');
    signal cam_wr_rate      : std_logic_vector(1 downto 0) := (others => '0');
    signal cam_rd_stretch   : std_logic := '0';
    signal cam_rd_cnt       : unsigned(23 downto 0) := (others => '0');
    signal vga_wr_stretch   : std_logic := '0';
    signal vga_wr_cnt       : unsigned(23 downto 0) := (others => '0');
    signal vga_full_seen    : std_logic := '0';
    signal vga_full_win_cnt : unsigned(23 downto 0) := (others => '0');

    signal cam_vsync_mapped : std_logic;
    signal cam_href_mapped  : std_logic;

    signal bypass_mode          : std_logic;
    signal cam_fifo_rd_en_to_cam: std_logic;
    signal cam_rd_en_bypass     : std_logic := '0';
    signal cam_rd_pending_bypass: std_logic := '0';
    signal vga_wr_en_bypass     : std_logic := '0';
    signal vga_wr_data_bypass   : std_logic_vector(15 downto 0) := (others => '0');

    signal vga_fifo_wr_en_to_vga   : std_logic;
    signal vga_fifo_wr_data_to_vga : std_logic_vector(15 downto 0);

    signal cam_fifo_empty_to_sdram    : std_logic;
    signal cam_fifo_rd_usedw_to_sdram : std_logic_vector(8 downto 0);
    signal vga_fifo_full_to_sdram     : std_logic;

    -- Probe signal
    signal debug_probe_bus  : std_logic_vector(31 downto 0);
    signal debug_geom_bus   : std_logic_vector(31 downto 0);
    signal debug_pix_bus    : std_logic_vector(31 downto 0);
    signal debug_bar01_bus  : std_logic_vector(31 downto 0);
    signal debug_bar23_bus  : std_logic_vector(31 downto 0);
    signal debug_bar45_bus  : std_logic_vector(31 downto 0);
    signal debug_bar67_bus  : std_logic_vector(31 downto 0);
    signal debug_line0_bus  : std_logic_vector(31 downto 0);
    signal debug_line60_bus : std_logic_vector(31 downto 0);
    signal debug_line120_bus: std_logic_vector(31 downto 0);
    signal debug_line180_bus: std_logic_vector(31 downto 0);
    signal debug_ol0_bus    : std_logic_vector(31 downto 0);
    signal debug_ol60_bus   : std_logic_vector(31 downto 0);
    signal debug_ol120_bus  : std_logic_vector(31 downto 0);
    signal debug_ol180_bus  : std_logic_vector(31 downto 0);
    signal debug_rl0_bus    : std_logic_vector(31 downto 0);
    signal debug_rl60_bus   : std_logic_vector(31 downto 0);
    signal debug_rl120_bus  : std_logic_vector(31 downto 0);
    signal debug_rl180_bus  : std_logic_vector(31 downto 0);
    signal debug_cfg0_bus   : std_logic_vector(31 downto 0);
    signal debug_cfg1_bus   : std_logic_vector(31 downto 0);
    signal debug_cfg2_bus   : std_logic_vector(31 downto 0);
    signal debug_cfg3_bus   : std_logic_vector(31 downto 0);
    signal debug_cfr01_bus  : std_logic_vector(31 downto 0);
    signal debug_cfr23_bus  : std_logic_vector(31 downto 0);
    signal debug_cfr45_bus  : std_logic_vector(31 downto 0);
    signal debug_cfr67_bus  : std_logic_vector(31 downto 0);
    signal debug_vgr01_bus  : std_logic_vector(31 downto 0);
    signal debug_vgr23_bus  : std_logic_vector(31 downto 0);
    signal debug_vgr45_bus  : std_logic_vector(31 downto 0);
    signal debug_vgr67_bus  : std_logic_vector(31 downto 0);
    signal debug_vgl0_bus   : std_logic_vector(31 downto 0);
    signal debug_vgl60_bus  : std_logic_vector(31 downto 0);
    signal debug_vgl120_bus : std_logic_vector(31 downto 0);
    signal debug_vgl180_bus : std_logic_vector(31 downto 0);
    signal debug_sch_bus    : std_logic_vector(31 downto 0);
    signal debug_ogr01_bus  : std_logic_vector(31 downto 0);
    signal debug_ogr23_bus  : std_logic_vector(31 downto 0);
    signal debug_ogr45_bus  : std_logic_vector(31 downto 0);
    signal debug_ogr67_bus  : std_logic_vector(31 downto 0);
    signal debug_vgst_bus   : std_logic_vector(31 downto 0);
    signal debug_rdr01_bus  : std_logic_vector(31 downto 0);
    signal debug_rdr23_bus  : std_logic_vector(31 downto 0);
    signal debug_rdr45_bus  : std_logic_vector(31 downto 0);
    signal debug_rdr67_bus  : std_logic_vector(31 downto 0);
    signal debug_uflo_bus   : std_logic_vector(31 downto 0);
    signal debug_camr01_bus : std_logic_vector(31 downto 0);
    signal debug_camr23_bus : std_logic_vector(31 downto 0);
    signal debug_camr45_bus : std_logic_vector(31 downto 0);
    signal debug_camr67_bus : std_logic_vector(31 downto 0);
    signal sdram_cfr01_dbg  : std_logic_vector(31 downto 0) := (others => '0');
    signal sdram_cfr23_dbg  : std_logic_vector(31 downto 0) := (others => '0');
    signal sdram_cfr45_dbg  : std_logic_vector(31 downto 0) := (others => '0');
    signal sdram_cfr67_dbg  : std_logic_vector(31 downto 0) := (others => '0');
    signal sdram_vgr01_dbg  : std_logic_vector(31 downto 0) := (others => '0');
    signal sdram_vgr23_dbg  : std_logic_vector(31 downto 0) := (others => '0');
    signal sdram_vgr45_dbg  : std_logic_vector(31 downto 0) := (others => '0');
    signal sdram_vgr67_dbg  : std_logic_vector(31 downto 0) := (others => '0');
    signal sdram_vgl0_dbg   : std_logic_vector(31 downto 0) := (others => '0');
    signal sdram_vgl60_dbg  : std_logic_vector(31 downto 0) := (others => '0');
    signal sdram_vgl120_dbg : std_logic_vector(31 downto 0) := (others => '0');
    signal sdram_vgl180_dbg : std_logic_vector(31 downto 0) := (others => '0');
    signal sdram_sch_dbg    : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_out01_dbg    : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_out23_dbg    : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_out45_dbg    : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_out67_dbg    : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_out_line0_dbg   : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_out_line60_dbg  : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_out_line120_dbg : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_out_line180_dbg : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_read_line0_dbg   : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_read_line60_dbg  : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_read_line120_dbg : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_read_line180_dbg : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_rdr01_dbg    : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_rdr23_dbg    : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_rdr45_dbg    : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_rdr67_dbg    : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_underflow_dbg : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_fifo_rd_en_dbg  : std_logic := '0';
    signal vga_fifo_empty_dbg  : std_logic := '1';
    signal vga_fifo_usedw_dbg  : std_logic_vector(11 downto 0) := (others => '0');
    signal vga_h_count_dbg     : std_logic_vector(9 downto 0) := (others => '0');
    signal vga_v_count_dbg     : std_logic_vector(9 downto 0) := (others => '0');
    signal cam_fifo_ref01_dbg : std_logic_vector(31 downto 0) := (others => '0');
    signal cam_fifo_ref23_dbg : std_logic_vector(31 downto 0) := (others => '0');
    signal cam_fifo_ref45_dbg : std_logic_vector(31 downto 0) := (others => '0');
    signal cam_fifo_ref67_dbg : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_wr_ref01_dbg   : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_wr_ref23_dbg   : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_wr_ref45_dbg   : std_logic_vector(31 downto 0) := (others => '0');
    signal vga_wr_ref67_dbg   : std_logic_vector(31 downto 0) := (others => '0');
    signal cam_fifo_ref_arm   : std_logic := '0';
    signal vga_wr_ref_arm     : std_logic := '0';
    signal cam_fifo_ref_idx   : unsigned(8 downto 0) := (others => '0');
    signal vga_wr_ref_idx     : unsigned(8 downto 0) := (others => '0');
    signal vga_vs_dbg_s1      : std_logic := '1';
    signal vga_vs_dbg_s2      : std_logic := '1';

begin

    DRAM_UDQM <= sdram_dqm(1);
    DRAM_LDQM <= sdram_dqm(0);
    DRAM_CLK  <= clk_dram;

    ov7670_xclk_sel <= SW(5 downto 4);

    p_xclk_div : process(clk_25m, rst_n)
    begin
        if rst_n = '0' then
            ov7670_xclk_cnt <= (others => '0');
        elsif rising_edge(clk_25m) then
            ov7670_xclk_cnt <= ov7670_xclk_cnt + 1;
        end if;
    end process;

    with ov7670_xclk_sel select ov7670_xclk_out <=
        clk_25m             when "00",  -- 25 MHz
        ov7670_xclk_cnt(0)  when "01",  -- 12.5 MHz
        ov7670_xclk_cnt(1)  when "10",  -- 6.25 MHz
        ov7670_xclk_cnt(2)  when others;-- 3.125 MHz

    OV7670_XCLK <= ov7670_xclk_out;

    bypass_mode <= SW(3);

    cam_vsync_mapped <= OV7670_VSYNC;
    cam_href_mapped  <= OV7670_HREF;

    cam_fifo_empty_to_sdram    <= '1' when bypass_mode = '1' else cam_fifo_empty;
    cam_fifo_rd_usedw_to_sdram <= (others => '0') when bypass_mode = '1' else cam_fifo_rd_usedw;
    vga_fifo_full_to_sdram     <= '1' when bypass_mode = '1' else vga_fifo_full;

    cam_fifo_rd_en_to_cam <= cam_rd_en_bypass when bypass_mode = '1' else cam_fifo_rd_en_sdram;
    vga_fifo_wr_en_to_vga <= vga_wr_en_bypass when bypass_mode = '1' else vga_fifo_wr_en_sdram;
    vga_fifo_wr_data_to_vga <= vga_wr_data_bypass when bypass_mode = '1' else vga_fifo_wr_data_sdram;

    p_bypass : process(clk_100m, rst_n)
	begin
		if rst_n = '0' then
			cam_rd_en_bypass     <= '0';
			cam_rd_pending_bypass <= '0';
			vga_wr_en_bypass   <= '0';
			vga_wr_data_bypass <= (others => '0');
		elsif rising_edge(clk_100m) then
			cam_rd_en_bypass <= '0';
			vga_wr_en_bypass <= '0';

			if cam_rd_pending_bypass = '1' then
				vga_wr_data_bypass <= cam_fifo_rd_data;
				if vga_fifo_full = '0' then
					vga_wr_en_bypass <= '1';
				end if;
				cam_rd_pending_bypass <= '0';
			elsif bypass_mode = '1' and cam_fifo_empty = '0' and vga_fifo_full = '0' then
				cam_rd_en_bypass      <= '1';
				cam_rd_pending_bypass <= '1';
			end if;
		end if;
	end process;

    -- =========================================================================
    -- Debug LEDs & Test Modes
    -- =========================================================================
    vga_test_mode(0) <= SW(0);
    vga_test_mode(1) <= '0';

    LEDR(0) <= pll_locked;
    LEDR(1) <= rst_n;
    LEDR(2) <= i2c_done;
    LEDR(3) <= SW(0);               -- VGA test pattern (color bars) when ON
    -- SW(1): invert OV7670 VSYNC+HREF if LED7 blinks fast and LED6 stays ON
    cam_fifo_has_data <= '0' when cam_fifo_empty = '1' else '1';

    LEDR(4) <= cam_fifo_rd_en_to_cam;       -- draining camera FIFO (SDRAM or bypass)
    LEDR(5) <= cam_fifo_has_data;    -- '1' = pixels waiting in camera FIFO
    LEDR(6) <= cam_fifo_empty;      -- '0' when camera is filling FIFO
    LEDR(7) <= frame_valid_stretch;  -- good camera frame captured (~200ms pulse)
    LEDR(8) <= cam_pclk_heartbeat;   -- ~3Hz if PCLK ~12MHz
    LEDR(9) <= vga_vs_int;

    -- Stretch frame_done / frame_valid edges in the 100 MHz domain for LEDs.
    p_stretch : process(clk_100m, rst_n)
    begin
        if rst_n = '0' then
            frame_done_s1       <= '0';
            frame_done_s2       <= '0';
            frame_valid_s1      <= '0';
            frame_valid_s2      <= '0';
            frame_done_stretch  <= '0';
            frame_valid_stretch <= '0';
            stretch_cnt         <= (others => '0');
            valid_stretch_cnt   <= (others => '0');
        elsif rising_edge(clk_100m) then
            frame_done_s1  <= frame_done;
            frame_done_s2  <= frame_done_s1;
            frame_valid_s1 <= cam_frame_valid_dbg;
            frame_valid_s2 <= frame_valid_s1;

            if frame_done_s1 = '1' and frame_done_s2 = '0' then
                frame_done_stretch <= '1';
                stretch_cnt        <= to_unsigned(20_000_000, 24);
            elsif stretch_cnt > 0 then
                stretch_cnt <= stretch_cnt - 1;
            else
                frame_done_stretch <= '0';
            end if;

            if frame_valid_s1 = '1' and frame_valid_s2 = '0' then
                frame_valid_stretch <= '1';
                valid_stretch_cnt   <= to_unsigned(20_000_000, 24);
            elsif valid_stretch_cnt > 0 then
                valid_stretch_cnt <= valid_stretch_cnt - 1;
            else
                frame_valid_stretch <= '0';
            end if;
        end if;
    end process;

    p_wr_stretch : process(clk_100m, rst_n)
    begin
        if rst_n = '0' then
            cam_wr_stretch <= '0';
            cam_wr_cnt     <= (others => '0');
        elsif rising_edge(clk_100m) then
            if cam_fifo_wr_pulse = '1' then
                cam_wr_stretch <= '1';
                cam_wr_cnt     <= to_unsigned(10_000_000, 24);
            elsif cam_wr_cnt > 0 then
                cam_wr_cnt <= cam_wr_cnt - 1;
            else
                cam_wr_stretch <= '0';
            end if;
        end if;
    end process;

    p_wr_rate : process(clk_100m, rst_n)
    begin
        if rst_n = '0' then
            cam_wr_edge_cnt <= (others => '0');
            cam_wr_win_cnt  <= (others => '0');
            cam_wr_rate     <= (others => '0');
        elsif rising_edge(clk_100m) then
            if cam_fifo_wr_pulse = '1' and cam_wr_edge_cnt /= to_unsigned(16_777_215, 24) then
                cam_wr_edge_cnt <= cam_wr_edge_cnt + 1;
            end if;

            if cam_wr_win_cnt = to_unsigned(10_000_000 - 1, 24) then
                if cam_wr_edge_cnt = 0 then
                    cam_wr_rate <= "00";
                elsif cam_wr_edge_cnt < to_unsigned(5_000, 24) then
                    cam_wr_rate <= "01";
                elsif cam_wr_edge_cnt < to_unsigned(50_000, 24) then
                    cam_wr_rate <= "10";
                else
                    cam_wr_rate <= "11";
                end if;
                cam_wr_edge_cnt <= (others => '0');
                cam_wr_win_cnt  <= (others => '0');
            else
                cam_wr_win_cnt <= cam_wr_win_cnt + 1;
            end if;
        end if;
    end process;

    p_rd_stretch : process(clk_100m, rst_n)
    begin
        if rst_n = '0' then
            cam_rd_stretch <= '0';
            cam_rd_cnt     <= (others => '0');
        elsif rising_edge(clk_100m) then
            if cam_fifo_rd_en_to_cam = '1' then
                cam_rd_stretch <= '1';
                cam_rd_cnt     <= to_unsigned(10_000_000, 24);
            elsif cam_rd_cnt > 0 then
                cam_rd_cnt <= cam_rd_cnt - 1;
            else
                cam_rd_stretch <= '0';
            end if;
        end if;
    end process;

    p_vga_wr_stretch : process(clk_100m, rst_n)
    begin
        if rst_n = '0' then
            vga_wr_stretch <= '0';
            vga_wr_cnt     <= (others => '0');
        elsif rising_edge(clk_100m) then
            if vga_fifo_wr_en_to_vga = '1' then
                vga_wr_stretch <= '1';
                vga_wr_cnt     <= to_unsigned(10_000_000, 24);
            elsif vga_wr_cnt > 0 then
                vga_wr_cnt <= vga_wr_cnt - 1;
            else
                vga_wr_stretch <= '0';
            end if;
        end if;
    end process;

    p_vga_full_seen : process(clk_100m, rst_n)
    begin
        if rst_n = '0' then
            vga_full_seen    <= '0';
            vga_full_win_cnt <= (others => '0');
        elsif rising_edge(clk_100m) then
            if vga_fifo_full = '1' then
                vga_full_seen <= '1';
            end if;

            if vga_full_win_cnt = to_unsigned(10_000_000 - 1, 24) then
                vga_full_seen    <= '0';
                vga_full_win_cnt <= (others => '0');
            else
                vga_full_win_cnt <= vga_full_win_cnt + 1;
            end if;
        end if;
    end process;

    p_downstream_refs : process(clk_100m, rst_n)
    begin
        if rst_n = '0' then
            cam_fifo_ref01_dbg <= (others => '0');
            cam_fifo_ref23_dbg <= (others => '0');
            cam_fifo_ref45_dbg <= (others => '0');
            cam_fifo_ref67_dbg <= (others => '0');
            vga_wr_ref01_dbg   <= (others => '0');
            vga_wr_ref23_dbg   <= (others => '0');
            vga_wr_ref45_dbg   <= (others => '0');
            vga_wr_ref67_dbg   <= (others => '0');
            cam_fifo_ref_arm   <= '0';
            vga_wr_ref_arm     <= '0';
            cam_fifo_ref_idx   <= (others => '0');
            vga_wr_ref_idx     <= (others => '0');
            vga_vs_dbg_s1      <= '1';
            vga_vs_dbg_s2      <= '1';
        elsif rising_edge(clk_100m) then
            vga_vs_dbg_s1 <= vga_vs_int;
            vga_vs_dbg_s2 <= vga_vs_dbg_s1;

            if frame_done_s1 = '1' and frame_done_s2 = '0' then
                cam_fifo_ref01_dbg <= (others => '0');
                cam_fifo_ref23_dbg <= (others => '0');
                cam_fifo_ref45_dbg <= (others => '0');
                cam_fifo_ref67_dbg <= (others => '0');
                cam_fifo_ref_arm   <= '1';
                cam_fifo_ref_idx   <= (others => '0');
            end if;

            if vga_vs_dbg_s2 = '1' and vga_vs_dbg_s1 = '0' then
                vga_wr_ref01_dbg <= (others => '0');
                vga_wr_ref23_dbg <= (others => '0');
                vga_wr_ref45_dbg <= (others => '0');
                vga_wr_ref67_dbg <= (others => '0');
                vga_wr_ref_arm   <= '1';
                vga_wr_ref_idx   <= (others => '0');
            end if;

            if cam_fifo_ref_arm = '1' and cam_fifo_rd_en_to_cam = '1' then
                case to_integer(cam_fifo_ref_idx) is
                    when 20  => cam_fifo_ref01_dbg(31 downto 16) <= cam_fifo_rd_data;
                    when 60  => cam_fifo_ref01_dbg(15 downto 0)  <= cam_fifo_rd_data;
                    when 100 => cam_fifo_ref23_dbg(31 downto 16) <= cam_fifo_rd_data;
                    when 140 => cam_fifo_ref23_dbg(15 downto 0)  <= cam_fifo_rd_data;
                    when 180 => cam_fifo_ref45_dbg(31 downto 16) <= cam_fifo_rd_data;
                    when 220 => cam_fifo_ref45_dbg(15 downto 0)  <= cam_fifo_rd_data;
                    when 260 => cam_fifo_ref67_dbg(31 downto 16) <= cam_fifo_rd_data;
                    when 300 => cam_fifo_ref67_dbg(15 downto 0)  <= cam_fifo_rd_data;
                    when others => null;
                end case;

                if cam_fifo_ref_idx = to_unsigned(300, cam_fifo_ref_idx'length) then
                    cam_fifo_ref_arm <= '0';
                else
                    cam_fifo_ref_idx <= cam_fifo_ref_idx + 1;
                end if;
            end if;

            if vga_wr_ref_arm = '1' and vga_fifo_wr_en_to_vga = '1' then
                case to_integer(vga_wr_ref_idx) is
                    when 20  => vga_wr_ref01_dbg(31 downto 16) <= vga_fifo_wr_data_to_vga;
                    when 60  => vga_wr_ref01_dbg(15 downto 0)  <= vga_fifo_wr_data_to_vga;
                    when 100 => vga_wr_ref23_dbg(31 downto 16) <= vga_fifo_wr_data_to_vga;
                    when 140 => vga_wr_ref23_dbg(15 downto 0)  <= vga_fifo_wr_data_to_vga;
                    when 180 => vga_wr_ref45_dbg(31 downto 16) <= vga_fifo_wr_data_to_vga;
                    when 220 => vga_wr_ref45_dbg(15 downto 0)  <= vga_fifo_wr_data_to_vga;
                    when 260 => vga_wr_ref67_dbg(31 downto 16) <= vga_fifo_wr_data_to_vga;
                    when 300 => vga_wr_ref67_dbg(15 downto 0)  <= vga_fifo_wr_data_to_vga;
                    when others => null;
                end case;

                if vga_wr_ref_idx = to_unsigned(300, vga_wr_ref_idx'length) then
                    vga_wr_ref_arm <= '0';
                else
                    vga_wr_ref_idx <= vga_wr_ref_idx + 1;
                end if;
            end if;
        end if;
    end process;

    p_cam_activity : process(clk_100m, rst_n)
        constant WIN_MAX : unsigned(24 downto 0) := to_unsigned(18_750_000 - 1, 25);
    begin
        if rst_n = '0' then
            pclk_sync1    <= '0';
            pclk_sync2    <= '0';
            vsync_sync1   <= '0';
            vsync_sync2   <= '0';
            href_sync1    <= '0';
            href_sync2    <= '0';
            pclk_prev     <= '0';
            vsync_prev    <= '0';
            href_prev     <= '0';
            pclk_edges    <= (others => '0');
            vsync_edges   <= (others => '0');
            href_edges    <= (others => '0');
            win_cnt       <= (others => '0');
            pclk_present  <= '0';
            vsync_present <= '0';
            href_present  <= '0';
        elsif rising_edge(clk_100m) then
            pclk_sync1  <= OV7670_PCLK;
            pclk_sync2  <= pclk_sync1;
            vsync_sync1 <= OV7670_VSYNC;
            vsync_sync2 <= vsync_sync1;
            href_sync1  <= OV7670_HREF;
            href_sync2  <= href_sync1;

            if (pclk_sync2 xor pclk_prev) = '1' then
                pclk_edges <= pclk_edges + 1;
            end if;
            if (vsync_sync2 = '1' and vsync_prev = '0') then
                vsync_edges <= vsync_edges + 1;
            end if;
            if (href_sync2 xor href_prev) = '1' then
                href_edges <= href_edges + 1;
            end if;

            pclk_prev  <= pclk_sync2;
            vsync_prev <= vsync_sync2;
            href_prev  <= href_sync2;

            if win_cnt = WIN_MAX then
                if pclk_edges > to_unsigned(1000, pclk_edges'length) then
                    pclk_present <= '1';
                else
                    pclk_present <= '0';
                end if;

                if vsync_edges > to_unsigned(0, vsync_edges'length) then
                    vsync_present <= '1';
                else
                    vsync_present <= '0';
                end if;

                if href_edges > to_unsigned(10, href_edges'length) then
                    href_present <= '1';
                else
                    href_present <= '0';
                end if;
                pclk_edges    <= (others => '0');
                vsync_edges   <= (others => '0');
                href_edges    <= (others => '0');
                win_cnt       <= (others => '0');
            else
                win_cnt <= win_cnt + 1;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- u_pll : PLL — all clocks from one ALTPLL instance
    -- =========================================================================
    u_pll : pll_main
        port map (
            inclk0  => MAX10_CLK1_50,
            c0      => clk_100m,
            c1      => clk_dram,
            c2      => clk_25m,
            locked  => pll_locked
        );

    -- =========================================================================
    -- u_sys : System controller — reset + debounce
    -- =========================================================================
    u_sys : sys_ctrl
        port map (
            clk_50m    => MAX10_CLK1_50,
            pll_locked => pll_locked,
            key0       => KEY(0),
            rst_n      => rst_n,
            locked_led => open
        );

    -- =========================================================================
    -- u_cam : Camera subsystem — OV7670 capture
    -- =========================================================================
    u_cam : camera_subsystem
        generic map (
            USE_VENDOR_FIFO => true
        )
        port map (
            clk_24m      => clk_25m,
            clk_130m     => clk_100m,
            rst_n        => rst_n,
            invert_sync  => SW(1),
            sample_falling => SW(2),
            reverse_bits => SW(6),
            data_map_sel => SW(9 downto 8),
            swap_bytes   => SW(7),
            cam_pclk     => OV7670_PCLK,
            cam_vsync    => cam_vsync_mapped,
            cam_href     => cam_href_mapped,
            cam_d        => OV7670_D,
            cam_xclk     => open,
            cam_sioc     => OV7670_SIOC,
            cam_siod     => OV7670_SIOD,
            cam_rst_n    => OV7670_RESET_N,
            cam_pwdn     => OV7670_PWDN,
            fifo_rd_en   => cam_fifo_rd_en_to_cam,
            fifo_rd_data => cam_fifo_rd_data,
            fifo_empty     => cam_fifo_empty,
            fifo_rd_usedw  => cam_fifo_rd_usedw,
            frame_done     => frame_done,
            i2c_done       => i2c_done,
            pclk_heartbeat => cam_pclk_heartbeat,
            fifo_wr_pulse  => cam_fifo_wr_pulse,
            last_line_count      => cam_last_line_count,
            last_pixel_count_div => cam_last_pixel_count_div,
            frame_valid_dbg      => cam_frame_valid_dbg,
            raw_byte_dbg         => cam_raw_byte_dbg,
            mapped_byte_dbg      => cam_mapped_byte_dbg,
            pixel_word_dbg       => cam_pixel_word_dbg,
            ref_pixels01_dbg     => cam_ref_pixels01_dbg,
            ref_pixels23_dbg     => cam_ref_pixels23_dbg,
            ref_pixels45_dbg     => cam_ref_pixels45_dbg,
            ref_pixels67_dbg     => cam_ref_pixels67_dbg,
            line0_pair_dbg       => cam_line0_pair_dbg,
            line60_pair_dbg      => cam_line60_pair_dbg,
            line120_pair_dbg     => cam_line120_pair_dbg,
            line180_pair_dbg     => cam_line180_pair_dbg,
            reg_cfg0_dbg         => cam_reg_cfg0_dbg,
            reg_cfg1_dbg         => cam_reg_cfg1_dbg,
            reg_cfg2_dbg         => cam_reg_cfg2_dbg,
            reg_cfg3_dbg         => cam_reg_cfg3_dbg
        );

    -- =========================================================================
    -- u_sdram : SDRAM subsystem — frame buffer arbitrator + IS42S16320F driver
    -- =========================================================================
    u_sdram : sdram_subsystem
        port map (
            clk_130m         => clk_100m,
            rst_n            => rst_n,
            test_mode        => sdram_test_mode,
            test_leds        => sdram_test_leds,
            bist_release_n   => KEY(1),
            cam_fifo_rd_en   => cam_fifo_rd_en_sdram,
            cam_fifo_rd_data => cam_fifo_rd_data,
            cam_fifo_empty   => cam_fifo_empty_to_sdram,
            cam_fifo_rd_usedw=> cam_fifo_rd_usedw_to_sdram,
            frame_done_async => frame_done,
            vga_vsync_async  => vga_vs_int,
            vga_fifo_wr_en   => vga_fifo_wr_en_sdram,
            vga_fifo_wr_data => vga_fifo_wr_data_sdram,
            vga_fifo_full    => vga_fifo_full_to_sdram,
            debug_cfr01_dbg  => sdram_cfr01_dbg,
            debug_cfr23_dbg  => sdram_cfr23_dbg,
            debug_cfr45_dbg  => sdram_cfr45_dbg,
            debug_cfr67_dbg  => sdram_cfr67_dbg,
            debug_vgr01_dbg  => sdram_vgr01_dbg,
            debug_vgr23_dbg  => sdram_vgr23_dbg,
            debug_vgr45_dbg  => sdram_vgr45_dbg,
            debug_vgr67_dbg  => sdram_vgr67_dbg,
            debug_vgl0_dbg   => sdram_vgl0_dbg,
            debug_vgl60_dbg  => sdram_vgl60_dbg,
            debug_vgl120_dbg => sdram_vgl120_dbg,
            debug_vgl180_dbg => sdram_vgl180_dbg,
            debug_sch_dbg    => sdram_sch_dbg,
            sdram_cke        => DRAM_CKE,
            sdram_cs_n       => DRAM_CS_N,
            sdram_ras_n      => DRAM_RAS_N,
            sdram_cas_n      => DRAM_CAS_N,
            sdram_we_n       => DRAM_WE_N,
            sdram_ba         => DRAM_BA,
            sdram_addr       => DRAM_ADDR,
            sdram_dqm        => sdram_dqm,
            sdram_dq         => DRAM_DQ
        );

    -- =========================================================================
    -- u_vga : VGA subsystem — pixel output to monitor
    -- =========================================================================
    u_vga : vga_subsystem
        generic map (
            USE_VENDOR_FIFO => true
        )
        port map (
            clk_25m      => clk_25m,
            clk_130m     => clk_100m,
            rst_n        => rst_n,
            test_mode    => vga_test_mode,
            fifo_wr_en   => vga_fifo_wr_en_to_vga,
            fifo_wr_data => vga_fifo_wr_data_to_vga,
            fifo_full    => vga_fifo_full,
            vga_r        => VGA_R,
            vga_g        => VGA_G,
            vga_b        => VGA_B,
            vga_hs       => VGA_HS,
            vga_vs       => vga_vs_int,
            fifo_rd_en_dbg   => vga_fifo_rd_en_dbg,
            fifo_empty_dbg   => vga_fifo_empty_dbg,
            fifo_usedw_dbg   => vga_fifo_usedw_dbg,
            h_count_dbg      => vga_h_count_dbg,
            v_count_dbg      => vga_v_count_dbg,
            out_pixels01_dbg  => vga_out01_dbg,
            out_pixels23_dbg  => vga_out23_dbg,
            out_pixels45_dbg  => vga_out45_dbg,
            out_pixels67_dbg  => vga_out67_dbg,
            read_pixels01_dbg => vga_rdr01_dbg,
            read_pixels23_dbg => vga_rdr23_dbg,
            read_pixels45_dbg => vga_rdr45_dbg,
            read_pixels67_dbg => vga_rdr67_dbg,
            read_line0_pair_dbg   => vga_read_line0_dbg,
            read_line60_pair_dbg  => vga_read_line60_dbg,
            read_line120_pair_dbg => vga_read_line120_dbg,
            read_line180_pair_dbg => vga_read_line180_dbg,
            underflow_count_dbg => vga_underflow_dbg,
            out_line0_pair_dbg   => vga_out_line0_dbg,
            out_line60_pair_dbg  => vga_out_line60_dbg,
            out_line120_pair_dbg => vga_out_line120_dbg,
            out_line180_pair_dbg => vga_out_line180_dbg
        );

    VGA_VS <= vga_vs_int;

    -- =========================================================================
    -- Remote Debug Probe (ISSP)
    -- =========================================================================
    debug_probe_bus(0)  <= pll_locked;
    debug_probe_bus(1)  <= rst_n;
    debug_probe_bus(2)  <= i2c_done;
    debug_probe_bus(3)  <= cam_rd_stretch;
    debug_probe_bus(4)  <= vga_wr_stretch;
    debug_probe_bus(5)  <= vga_full_seen;
    debug_probe_bus(6)  <= cam_fifo_empty;
    debug_probe_bus(7)  <= cam_fifo_has_data;
    debug_probe_bus(8)  <= cam_fifo_rd_en_to_cam;
    debug_probe_bus(9)  <= vga_fifo_full;
    debug_probe_bus(10) <= vga_fifo_wr_en_to_vga;
    debug_probe_bus(11) <= frame_done;
    debug_probe_bus(12) <= frame_done_stretch;
    debug_probe_bus(13) <= cam_pclk_heartbeat;
    debug_probe_bus(14) <= vga_vs_int;
    debug_probe_bus(15) <= pclk_present;
    debug_probe_bus(16) <= vsync_present;
    debug_probe_bus(17) <= href_present;
    debug_probe_bus(18) <= cam_wr_stretch;
    debug_probe_bus(19) <= bypass_mode;
    debug_probe_bus(20) <= SW(4);
    debug_probe_bus(21) <= cam_wr_rate(0);
    debug_probe_bus(22) <= cam_wr_rate(1);
    debug_probe_bus(31 downto 23) <= cam_fifo_rd_usedw;

    debug_geom_bus(9 downto 0)   <= cam_last_line_count;
    debug_geom_bus(18 downto 10) <= cam_last_pixel_count_div;
    debug_geom_bus(19)           <= cam_frame_valid_dbg;
    debug_geom_bus(31 downto 20) <= (others => '0');
    debug_pix_bus(7 downto 0)    <= cam_raw_byte_dbg;
    debug_pix_bus(15 downto 8)   <= cam_mapped_byte_dbg;
    debug_pix_bus(31 downto 16)  <= cam_pixel_word_dbg;
    debug_bar01_bus              <= cam_ref_pixels01_dbg;
    debug_bar23_bus              <= cam_ref_pixels23_dbg;
    debug_bar45_bus              <= cam_ref_pixels45_dbg;
    debug_bar67_bus              <= cam_ref_pixels67_dbg;
    debug_line0_bus              <= cam_line0_pair_dbg;
    debug_line60_bus             <= cam_line60_pair_dbg;
    debug_line120_bus            <= cam_line120_pair_dbg;
    debug_line180_bus            <= cam_line180_pair_dbg;
    debug_ol0_bus                <= vga_out_line0_dbg;
    debug_ol60_bus               <= vga_out_line60_dbg;
    debug_ol120_bus              <= vga_out_line120_dbg;
    debug_ol180_bus              <= vga_out_line180_dbg;
    debug_rl0_bus                <= vga_read_line0_dbg;
    debug_rl60_bus               <= vga_read_line60_dbg;
    debug_rl120_bus              <= vga_read_line120_dbg;
    debug_rl180_bus              <= vga_read_line180_dbg;
    debug_cfg0_bus               <= cam_reg_cfg0_dbg;
    debug_cfg1_bus               <= cam_reg_cfg1_dbg;
    debug_cfg2_bus               <= cam_reg_cfg2_dbg;
    debug_cfg3_bus               <= cam_reg_cfg3_dbg;
    debug_cfr01_bus              <= sdram_cfr01_dbg;
    debug_cfr23_bus              <= sdram_cfr23_dbg;
    debug_cfr45_bus              <= sdram_cfr45_dbg;
    debug_cfr67_bus              <= sdram_cfr67_dbg;
    debug_vgr01_bus              <= sdram_vgr01_dbg;
    debug_vgr23_bus              <= sdram_vgr23_dbg;
    debug_vgr45_bus              <= sdram_vgr45_dbg;
    debug_vgr67_bus              <= sdram_vgr67_dbg;
    debug_vgl0_bus               <= sdram_vgl0_dbg;
    debug_vgl60_bus              <= sdram_vgl60_dbg;
    debug_vgl120_bus             <= sdram_vgl120_dbg;
    debug_vgl180_bus             <= sdram_vgl180_dbg;
    debug_sch_bus                <= sdram_sch_dbg;
    debug_ogr01_bus              <= vga_out01_dbg;
    debug_ogr23_bus              <= vga_out23_dbg;
    debug_ogr45_bus              <= vga_out45_dbg;
    debug_ogr67_bus              <= vga_out67_dbg;
    debug_rdr01_bus              <= vga_rdr01_dbg;
    debug_rdr23_bus              <= vga_rdr23_dbg;
    debug_rdr45_bus              <= vga_rdr45_dbg;
    debug_rdr67_bus              <= vga_rdr67_dbg;
    debug_uflo_bus               <= vga_underflow_dbg;
    debug_camr01_bus             <= cam_fifo_ref01_dbg;
    debug_camr23_bus             <= cam_fifo_ref23_dbg;
    debug_camr45_bus             <= cam_fifo_ref45_dbg;
    debug_camr67_bus             <= cam_fifo_ref67_dbg;

    debug_vgst_bus(9 downto 0)   <= vga_h_count_dbg;
    debug_vgst_bus(19 downto 10) <= vga_v_count_dbg;
    debug_vgst_bus(31 downto 20) <= vga_fifo_usedw_dbg(11 downto 0);

    u_debug : altsource_probe
        generic map (
            sld_instance_index => 0,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "STAT"
        )
        port map (
            source => open,
            probe  => debug_probe_bus
        );

    u_debug_geom : altsource_probe
        generic map (
            sld_instance_index => 1,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "GEOM"
        )
        port map (
            source => open,
            probe  => debug_geom_bus
        );

    u_debug_pix : altsource_probe
        generic map (
            sld_instance_index => 2,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "PIX"
        )
        port map (
            source => open,
            probe  => debug_pix_bus
        );

    u_debug_bar01 : altsource_probe
        generic map (
            sld_instance_index => 3,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "BAR0"
        )
        port map (
            source => open,
            probe  => debug_bar01_bus
        );

    u_debug_bar23 : altsource_probe
        generic map (
            sld_instance_index => 4,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "BAR1"
        )
        port map (
            source => open,
            probe  => debug_bar23_bus
        );

    u_debug_bar45 : altsource_probe
        generic map (
            sld_instance_index => 5,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "BAR2"
        )
        port map (
            source => open,
            probe  => debug_bar45_bus
        );

    u_debug_bar67 : altsource_probe
        generic map (
            sld_instance_index => 6,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "BAR3"
        )
        port map (
            source => open,
            probe  => debug_bar67_bus
        );

    u_debug_cfg0 : altsource_probe
        generic map (
            sld_instance_index => 7,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "CFG0"
        )
        port map (
            source => open,
            probe  => debug_cfg0_bus
        );

    u_debug_cfg1 : altsource_probe
        generic map (
            sld_instance_index => 8,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "CFG1"
        )
        port map (
            source => open,
            probe  => debug_cfg1_bus
        );

    u_debug_cfg2 : altsource_probe
        generic map (
            sld_instance_index => 9,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "CFG2"
        )
        port map (
            source => open,
            probe  => debug_cfg2_bus
        );

    u_debug_cfg3 : altsource_probe
        generic map (
            sld_instance_index => 10,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "CFG3"
        )
        port map (
            source => open,
            probe  => debug_cfg3_bus
        );

    u_debug_cfr01 : altsource_probe
        generic map (
            sld_instance_index => 11,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "CFR0"
        )
        port map (
            source => open,
            probe  => debug_cfr01_bus
        );

    u_debug_cfr23 : altsource_probe
        generic map (
            sld_instance_index => 12,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "CFR1"
        )
        port map (
            source => open,
            probe  => debug_cfr23_bus
        );

    u_debug_cfr45 : altsource_probe
        generic map (
            sld_instance_index => 13,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "CFR2"
        )
        port map (
            source => open,
            probe  => debug_cfr45_bus
        );

    u_debug_cfr67 : altsource_probe
        generic map (
            sld_instance_index => 14,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "CFR3"
        )
        port map (
            source => open,
            probe  => debug_cfr67_bus
        );

    u_debug_vgr01 : altsource_probe
        generic map (
            sld_instance_index => 15,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "VGR0"
        )
        port map (
            source => open,
            probe  => debug_vgr01_bus
        );

    u_debug_vgr23 : altsource_probe
        generic map (
            sld_instance_index => 16,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "VGR1"
        )
        port map (
            source => open,
            probe  => debug_vgr23_bus
        );

    u_debug_vgr45 : altsource_probe
        generic map (
            sld_instance_index => 17,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "VGR2"
        )
        port map (
            source => open,
            probe  => debug_vgr45_bus
        );

    u_debug_vgr67 : altsource_probe
        generic map (
            sld_instance_index => 18,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "VGR3"
        )
        port map (
            source => open,
            probe  => debug_vgr67_bus
        );

    u_debug_ogr01 : altsource_probe
        generic map (
            sld_instance_index => 19,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "OGR0"
        )
        port map (
            source => open,
            probe  => debug_ogr01_bus
        );

    u_debug_ogr23 : altsource_probe
        generic map (
            sld_instance_index => 20,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "OGR1"
        )
        port map (
            source => open,
            probe  => debug_ogr23_bus
        );

    u_debug_ogr45 : altsource_probe
        generic map (
            sld_instance_index => 21,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "OGR2"
        )
        port map (
            source => open,
            probe  => debug_ogr45_bus
        );

    u_debug_ogr67 : altsource_probe
        generic map (
            sld_instance_index => 22,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "OGR3"
        )
        port map (
            source => open,
            probe  => debug_ogr67_bus
        );

    u_debug_vgst : altsource_probe
        generic map (
            sld_instance_index => 23,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "VGST"
        )
        port map (
            source => open,
            probe  => debug_vgst_bus
        );

    u_debug_rdr01 : altsource_probe
        generic map (
            sld_instance_index => 24,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "RDR0"
        )
        port map (
            source => open,
            probe  => debug_rdr01_bus
        );

    u_debug_rdr23 : altsource_probe
        generic map (
            sld_instance_index => 25,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "RDR1"
        )
        port map (
            source => open,
            probe  => debug_rdr23_bus
        );

    u_debug_rdr45 : altsource_probe
        generic map (
            sld_instance_index => 26,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "RDR2"
        )
        port map (
            source => open,
            probe  => debug_rdr45_bus
        );

    u_debug_rdr67 : altsource_probe
        generic map (
            sld_instance_index => 27,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "RDR3"
        )
        port map (
            source => open,
            probe  => debug_rdr67_bus
        );

    u_debug_uflo : altsource_probe
        generic map (
            sld_instance_index => 28,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "UFLO"
        )
        port map (
            source => open,
            probe  => debug_uflo_bus
        );

    u_debug_camr01 : altsource_probe
        generic map (
            sld_instance_index => 29,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "CAMR0"
        )
        port map (
            source => open,
            probe  => debug_camr01_bus
        );

    u_debug_camr23 : altsource_probe
        generic map (
            sld_instance_index => 30,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "CAMR1"
        )
        port map (
            source => open,
            probe  => debug_camr23_bus
        );

    u_debug_camr45 : altsource_probe
        generic map (
            sld_instance_index => 31,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "CAMR2"
        )
        port map (
            source => open,
            probe  => debug_camr45_bus
        );

    u_debug_camr67 : altsource_probe
        generic map (
            sld_instance_index => 32,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "CAMR3"
        )
        port map (
            source => open,
            probe  => debug_camr67_bus
        );

    u_debug_line0 : altsource_probe
        generic map (
            sld_instance_index => 33,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "L0"
        )
        port map (
            source => open,
            probe  => debug_line0_bus
        );

    u_debug_line60 : altsource_probe
        generic map (
            sld_instance_index => 34,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "L60"
        )
        port map (
            source => open,
            probe  => debug_line60_bus
        );

    u_debug_line120 : altsource_probe
        generic map (
            sld_instance_index => 35,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "L120"
        )
        port map (
            source => open,
            probe  => debug_line120_bus
        );

    u_debug_line180 : altsource_probe
        generic map (
            sld_instance_index => 36,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "L180"
        )
        port map (
            source => open,
            probe  => debug_line180_bus
        );

    u_debug_ol0 : altsource_probe
        generic map (
            sld_instance_index => 37,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "OL0"
        )
        port map (
            source => open,
            probe  => debug_ol0_bus
        );

    u_debug_ol60 : altsource_probe
        generic map (
            sld_instance_index => 38,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "OL60"
        )
        port map (
            source => open,
            probe  => debug_ol60_bus
        );

    u_debug_ol120 : altsource_probe
        generic map (
            sld_instance_index => 39,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "OL120"
        )
        port map (
            source => open,
            probe  => debug_ol120_bus
        );

    u_debug_ol180 : altsource_probe
        generic map (
            sld_instance_index => 40,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "OL180"
        )
        port map (
            source => open,
            probe  => debug_ol180_bus
        );

    u_debug_vgl0 : altsource_probe
        generic map (
            sld_instance_index => 41,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "VGL0"
        )
        port map (
            source => open,
            probe  => debug_vgl0_bus
        );

    u_debug_vgl60 : altsource_probe
        generic map (
            sld_instance_index => 42,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "VGL60"
        )
        port map (
            source => open,
            probe  => debug_vgl60_bus
        );

    u_debug_vgl120 : altsource_probe
        generic map (
            sld_instance_index => 43,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "VGL120"
        )
        port map (
            source => open,
            probe  => debug_vgl120_bus
        );

    u_debug_vgl180 : altsource_probe
        generic map (
            sld_instance_index => 44,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "VGL180"
        )
        port map (
            source => open,
            probe  => debug_vgl180_bus
        );

    u_debug_rl0 : altsource_probe
        generic map (
            sld_instance_index => 45,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "RL0"
        )
        port map (
            source => open,
            probe  => debug_rl0_bus
        );

    u_debug_rl60 : altsource_probe
        generic map (
            sld_instance_index => 46,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "RL60"
        )
        port map (
            source => open,
            probe  => debug_rl60_bus
        );

    u_debug_rl120 : altsource_probe
        generic map (
            sld_instance_index => 47,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "RL12"
        )
        port map (
            source => open,
            probe  => debug_rl120_bus
        );

    u_debug_rl180 : altsource_probe
        generic map (
            sld_instance_index => 48,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "RL18"
        )
        port map (
            source => open,
            probe  => debug_rl180_bus
        );

    u_debug_sch : altsource_probe
        generic map (
            sld_instance_index => 49,
            source_width       => 1,
            probe_width        => 32,
            instance_id        => "SCH"
        )
        port map (
            source => open,
            probe  => debug_sch_bus
        );

end architecture rtl;
