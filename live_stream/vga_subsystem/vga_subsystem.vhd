-- =============================================================================
-- vga_subsystem.vhd
-- VGA output subsystem wrapper (25 MHz domain)
--
-- Contains:
--   u_fifo  : asyn_fifo      -- CDC bridge: 100 MHz write -> 25 MHz read
--   u_core  : vga_core       -- 640x480 @ 60Hz timing generator
--   u_iface : vga_interface  -- pixel fetch + 4-bit DAC drive
--
-- The FIFO write side (clk_130m, 100MHz) is fed by sdram_subsystem.
-- The FIFO read side and all VGA logic run on clk_25m.
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vga_subsystem is
    generic (
        USE_VENDOR_FIFO : boolean := false;
        -- Cap the write-side backlog to roughly one camera scanline (320
        -- pixels) plus burst margin, instead of letting it fill toward the
        -- full 4096-entry depth. A backlog anywhere near full survives a
        -- vsync bank swap intact and shows up as stale-frame content
        -- (tearing / lag) at the top of the next displayed frame.
        FIFO_ALMOST_FULL_THRESH : integer := 3072
    );
    port (
        -- Clocks
        clk_25m      : in  std_logic;   -- 25 MHz VGA pixel clock
        clk_130m     : in  std_logic;   -- 100 MHz FIFO write side
        rst_n        : in  std_logic;
        test_mode    : in  std_logic_vector(1 downto 0);

        -- FIFO write interface (from sdram_subsystem, 100 MHz domain)
        fifo_wr_en   : in  std_logic;
        fifo_wr_data : in  std_logic_vector(15 downto 0);
        fifo_full    : out std_logic;   -- back-pressure to sdram_subsystem

        -- DE10-Lite VGA connector
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
end entity vga_subsystem;

architecture rtl of vga_subsystem is
    -- Prefill before first frame; start reads only at active pixel (0,0).
    constant START_FILL_LEVEL : unsigned(11 downto 0) := to_unsigned(320, 12);

    -- -------------------------------------------------------------------------
    -- Component declarations
    -- -------------------------------------------------------------------------
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
            rd_usedw : out std_logic_vector(DEPTH_LOG2-1 downto 0);
            wr_usedw : out std_logic_vector(DEPTH_LOG2-1 downto 0)
        );
    end component;

    component vga_core
        port (
            pclk    : in  std_logic;
            rst_n   : in  std_logic;
            hsync   : out std_logic;
            vsync   : out std_logic;
            active  : out std_logic;
            h_count : out std_logic_vector(9 downto 0);
            v_count : out std_logic_vector(9 downto 0)
        );
    end component;

    component vga_interface
        port (
            pclk         : in  std_logic;
            rst_n        : in  std_logic;
            test_mode    : in  std_logic_vector(1 downto 0);
            rd_gate      : in  std_logic;
            fifo_rd_en   : out std_logic;
            fifo_rd_data : in  std_logic_vector(15 downto 0);
            fifo_empty   : in  std_logic;
            active       : in  std_logic;
            h_count      : in  std_logic_vector(9 downto 0);
            v_count      : in  std_logic_vector(9 downto 0);
            hsync_in     : in  std_logic;
            vsync_in     : in  std_logic;
            vga_r        : out std_logic_vector(3 downto 0);
            vga_g        : out std_logic_vector(3 downto 0);
            vga_b        : out std_logic_vector(3 downto 0);
            vga_hs       : out std_logic;
            vga_vs       : out std_logic;
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

    -- -------------------------------------------------------------------------
    -- Internal signals
    -- -------------------------------------------------------------------------
    signal fifo_rd_en_iface : std_logic;
    signal fifo_rd_en       : std_logic;
    signal fifo_rd_data  : std_logic_vector(15 downto 0);
    signal fifo_empty    : std_logic;
    signal fifo_usedw    : std_logic_vector(11 downto 0);
    signal fifo_wr_usedw : std_logic_vector(11 downto 0);
    signal fifo_wr_full  : std_logic;
    signal fifo_almost_full : std_logic;
    signal fifo_rst_n    : std_logic;
    signal read_start_armed : std_logic := '0';
    signal read_start_ready : std_logic := '0';
    signal vsync_d          : std_logic := '1';  -- previous vsync for edge detection
    signal vga_hsync     : std_logic;
    signal vga_vsync     : std_logic;
    signal vga_active    : std_logic;
    signal vga_h_count   : std_logic_vector(9 downto 0);
    signal vga_v_count   : std_logic_vector(9 downto 0);

    signal vsync_sync_wr1 : std_logic := '1';
    signal vsync_sync_wr2 : std_logic := '1';
    signal fifo_rst_n_wr  : std_logic;

begin

    fifo_rd_en <= fifo_rd_en_iface;
    fifo_rd_en_dbg <= fifo_rd_en;
    fifo_empty_dbg <= fifo_empty;
    fifo_usedw_dbg <= fifo_usedw;
    h_count_dbg <= vga_h_count;
    v_count_dbg <= vga_v_count;
    -- The SDRAM reader restarts at pixel 0 on every VGA VSYNC.  Reset the
    -- cross-clock FIFO for the same interval so it cannot retain tail pixels
    -- from the preceding frame; otherwise the next display frame begins at an
    -- arbitrary source-pixel offset (visible as scrambled colour bars).
    fifo_rst_n <= rst_n and vga_vsync;

    p_sync_wr_rst : process(clk_130m, rst_n)
    begin
        if rst_n = '0' then
            vsync_sync_wr1 <= '1';
            vsync_sync_wr2 <= '1';
        elsif rising_edge(clk_130m) then
            vsync_sync_wr1 <= vga_vsync;
            vsync_sync_wr2 <= vsync_sync_wr1;
        end if;
    end process;
    fifo_rst_n_wr <= rst_n and vsync_sync_wr2;

    -- Back-pressure the producer (sdram_interface, clk_130m domain) once the
    -- backlog crosses FIFO_ALMOST_FULL_THRESH, well before the FIFO is
    -- actually full. fifo_wr_usedw is a clk_130m-domain signal, and this
    -- comparison is evaluated in that same domain, so no extra CDC is
    -- introduced. fifo_wr_full is OR'd in as a hard backstop in case the
    -- threshold is ever misconfigured above the FIFO depth.
    fifo_almost_full <= '1' when (unsigned(fifo_wr_usedw) >= to_unsigned(FIFO_ALMOST_FULL_THRESH, fifo_wr_usedw'length))
                         else fifo_wr_full;
    fifo_full <= fifo_almost_full;


    p_read_start : process(clk_25m, rst_n)
    begin
        if rst_n = '0' then
            read_start_armed  <= '0';
            read_start_ready  <= '0';
            vsync_d           <= '1';
        elsif rising_edge(clk_25m) then
            vsync_d <= vga_vsync;

            -- Disarm on the FALLING EDGE of vsync only (one cycle pulse).
            -- Using level-sensitive disarm caused a deadlock: it fought the
            -- arming condition every clock cycle during the vsync pulse.
            if vga_vsync = '0' and vsync_d = '1' then
                read_start_armed <= '0';
                read_start_ready <= '0';
            end if;

            -- Set ready when the FIFO has any data at all.
            -- NOTE: We cannot use "fifo_usedw >= START_FILL_LEVEL" because
            -- Altera's dcfifo rdusedw wraps to 0 when the FIFO is completely
            -- full (4096 words → 4096 mod 4096 = 0). This caused a deadlock
            -- where the SDRAM filled the FIFO to capacity, rdusedw wrapped to
            -- 0, the check saw 0 >= 320 = FALSE, and the VGA never started
            -- reading, keeping the FIFO permanently full and the SDRAM stuck.
            -- Using fifo_usedw >= 320 is safe because we don't let it fill to 4096.
            if unsigned(fifo_usedw) >= to_unsigned(320, 12) then
                read_start_ready <= '1';
            end if;

            -- Arm during blanking (vga_active='0') AFTER vsync has gone high again.
            -- Requiring vga_vsync='1' ensures we never try to arm during the
            -- sync pulse itself, which could race with the disarm above.
            if read_start_armed = '0' and read_start_ready = '1' and
               vga_vsync = '1' and vga_active = '0' then
                read_start_armed <= '1';
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- Async FIFO: clk_130m write -> clk_25m read
    -- Physical depth is 4096 entries, but the producer is now held back at
    -- FIFO_ALMOST_FULL_THRESH (see fifo_almost_full above) so the backlog
    -- normally never exceeds ~1 camera scanline (320 pixels) plus burst
    -- margin. The full 4096-entry depth remains only as slack for bursts
    -- and a hard backstop, not the steady-state operating point.
    -- -------------------------------------------------------------------------
    u_fifo : asyn_fifo
        generic map (
            DATA_WIDTH => 16,
            DEPTH_LOG2 => 12,   -- 4096 entries
            USE_DCFIFO => USE_VENDOR_FIFO
        )
        port map (
            wr_clk   => clk_130m,
            wr_rst_n => fifo_rst_n_wr,
            wr_en    => fifo_wr_en,
            wr_data  => fifo_wr_data,
            wr_full  => fifo_wr_full,
            rd_clk   => clk_25m,
            rd_rst_n => fifo_rst_n,
            rd_en    => fifo_rd_en,
            rd_data  => fifo_rd_data,
            rd_empty => fifo_empty,
            rd_usedw => fifo_usedw,
            wr_usedw => fifo_wr_usedw
        );

    -- -------------------------------------------------------------------------
    -- VGA timing generator
    -- -------------------------------------------------------------------------
    u_core : vga_core
        port map (
            pclk    => clk_25m,
            rst_n   => rst_n,
            hsync   => vga_hsync,
            vsync   => vga_vsync,
            active  => vga_active,
            h_count => vga_h_count,
            v_count => vga_v_count
        );

    -- -------------------------------------------------------------------------
    -- VGA pixel output (reads FIFO, drives 4-bit DAC)
    -- -------------------------------------------------------------------------
    u_iface : vga_interface
        port map (
            pclk         => clk_25m,
            rst_n        => rst_n,
            test_mode    => test_mode,
            -- Start a frame only after data is present during blanking.  This
            -- keeps the first source pixel aligned with output coordinate
            -- (0, 0), rather than starting partway through an active frame.
            rd_gate      => read_start_armed,
            fifo_rd_en   => fifo_rd_en_iface,
            fifo_rd_data => fifo_rd_data,
            fifo_empty   => fifo_empty,
            active       => vga_active,
            h_count      => vga_h_count,
            v_count      => vga_v_count,
            hsync_in     => vga_hsync,
            vsync_in     => vga_vsync,
            vga_r        => vga_r,
            vga_g        => vga_g,
            vga_b        => vga_b,
            vga_hs       => vga_hs,
            vga_vs       => vga_vs,
            out_pixels01_dbg  => out_pixels01_dbg,
            out_pixels23_dbg  => out_pixels23_dbg,
            out_pixels45_dbg  => out_pixels45_dbg,
            out_pixels67_dbg  => out_pixels67_dbg,
            read_pixels01_dbg => read_pixels01_dbg,
            read_pixels23_dbg => read_pixels23_dbg,
            read_pixels45_dbg => read_pixels45_dbg,
            read_pixels67_dbg => read_pixels67_dbg,
            read_line0_pair_dbg   => read_line0_pair_dbg,
            read_line60_pair_dbg  => read_line60_pair_dbg,
            read_line120_pair_dbg => read_line120_pair_dbg,
            read_line180_pair_dbg => read_line180_pair_dbg,
            underflow_count_dbg => underflow_count_dbg,
            out_line0_pair_dbg   => out_line0_pair_dbg,
            out_line60_pair_dbg  => out_line60_pair_dbg,
            out_line120_pair_dbg => out_line120_pair_dbg,
            out_line180_pair_dbg => out_line180_pair_dbg
        );

end architecture rtl;
