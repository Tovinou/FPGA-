-- =============================================================================
-- sdram_subsystem.vhd
-- SDRAM subsystem wrapper (100 MHz domain)
--
-- Contains:
--   u_ctrl  : sdram_controller  -- low-level SDRAM command driver
--   u_iface : sdram_interface   -- frame-buffer arbitrator (write/read paths)
--
-- Data flow:
--   camera_subsystem FIFO  ->  sdram_interface  ->  sdram_controller  ->  SDRAM
--   SDRAM  ->  sdram_controller  ->  sdram_interface  ->  vga_subsystem FIFO
--
-- CDC notes:
--   frame_done arrives from camera_subsystem (PCLK domain).
--   It is re-synchronised here with a 2-FF synchroniser into clk_130m (100MHz).
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sdram_subsystem is
    port (
        -- Clock & reset
        clk_130m         : in    std_logic;  -- 75 MHz internal FSM clock (PLL c0)
        rst_n            : in    std_logic;
        test_mode        : out   std_logic_vector(1 downto 0);
        test_leds        : out   std_logic_vector(9 downto 0);
        bist_release_n   : in    std_logic;

        -- Camera FIFO read interface (written by camera_subsystem, PCLK domain)
        cam_fifo_rd_en   : out   std_logic;
        cam_fifo_rd_data : in    std_logic_vector(15 downto 0);
        cam_fifo_empty   : in    std_logic;
        cam_fifo_rd_usedw: in    std_logic_vector(8 downto 0);  -- DEPTH_LOG2=9

        -- Frame-done pulse from camera (PCLK domain -> re-synced here)
        frame_done_async : in    std_logic;
        vga_vsync_async  : in    std_logic;

        -- VGA FIFO write interface (read by vga_subsystem, 25 MHz domain)
        vga_fifo_wr_en   : out   std_logic;
        vga_fifo_wr_data : out   std_logic_vector(15 downto 0);
        vga_fifo_full    : in    std_logic;

        -- Debug reference samples from inside sdram_interface
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

        -- SDRAM physical pins -> DRAM_* top-level ports
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
end entity sdram_subsystem;

architecture rtl of sdram_subsystem is

    -- -------------------------------------------------------------------------
    -- Component declarations
    -- -------------------------------------------------------------------------
    component sdram_controller
        port (
            clk         : in    std_logic;
            rst_n       : in    std_logic;
            wr_req      : in    std_logic;
            wr_addr     : in    std_logic_vector(24 downto 0);
            wr_data     : in    std_logic_vector(127 downto 0);
            wr_ack      : out   std_logic;
            rd_req      : in    std_logic;
            rd_addr     : in    std_logic_vector(24 downto 0);
            rd_data     : out   std_logic_vector(15 downto 0);
            rd_valid    : out   std_logic;
            rd_ack      : out   std_logic;
            sdram_clk   : out   std_logic;
            sdram_cke   : out   std_logic;
            sdram_cs_n  : out   std_logic;
            sdram_ras_n : out   std_logic;
            sdram_cas_n : out   std_logic;
            sdram_we_n  : out   std_logic;
            sdram_ba    : out   std_logic_vector(1 downto 0);
            sdram_addr  : out   std_logic_vector(12 downto 0);
            sdram_dqm   : out   std_logic_vector(1 downto 0);
            sdram_dq    : inout std_logic_vector(15 downto 0)
        );
    end component;

    component sdram_interface
        port (
            clk              : in    std_logic;
            rst_n            : in    std_logic;
            cam_fifo_rd_en   : out std_logic;
            cam_fifo_rd_data : in  std_logic_vector(15 downto 0);
            cam_fifo_empty   : in  std_logic;
            cam_fifo_rd_usedw: in  std_logic_vector(8 downto 0);  -- DEPTH_LOG2=9
            vga_fifo_wr_en   : out std_logic;
            vga_fifo_wr_data : out   std_logic_vector(15 downto 0);
            vga_fifo_full    : in    std_logic;
            sdram_wr_req     : out   std_logic;
            sdram_wr_addr    : out   std_logic_vector(24 downto 0);
            sdram_wr_data    : out   std_logic_vector(127 downto 0);
            sdram_wr_ack     : in    std_logic;
            sdram_rd_req     : out   std_logic;
            sdram_rd_addr    : out   std_logic_vector(24 downto 0);
            sdram_rd_data    : in    std_logic_vector(15 downto 0);
            sdram_rd_valid   : in    std_logic;
            sdram_rd_ack     : in    std_logic;
            frame_done_sync  : in    std_logic;
            vga_vsync_sync   : in    std_logic;
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
            debug_sch_dbg    : out   std_logic_vector(31 downto 0)
        );
    end component;

    -- -------------------------------------------------------------------------
    -- Internal signals
    -- -------------------------------------------------------------------------

    -- Clock pass-through: PLL c1 routed to sdram_clk output
    -- This ensures DRAM_CLK is driven cleanly from the phase-shifted PLL output

    -- 2-FF synchroniser for frame_done (PCLK -> 75 MHz)
    signal frame_done_s1   : std_logic := '0';
    signal frame_done_s2   : std_logic := '0';
    signal vga_vsync_s1    : std_logic := '1';
    signal vga_vsync_s2    : std_logic := '1';

    -- sdram_interface <-> sdram_controller bus
    signal iface_wr_req          : std_logic;
    signal iface_wr_addr         : std_logic_vector(24 downto 0);
    signal iface_wr_data         : std_logic_vector(127 downto 0);
    signal iface_wr_ack          : std_logic;
    signal iface_rd_req          : std_logic;
    signal iface_rd_addr         : std_logic_vector(24 downto 0);
    signal iface_rd_data         : std_logic_vector(15 downto 0);
    signal iface_rd_valid        : std_logic;
    signal iface_rd_ack          : std_logic;

    signal ctrl_wr_req          : std_logic;
    signal ctrl_wr_addr         : std_logic_vector(24 downto 0);
    signal ctrl_wr_data         : std_logic_vector(127 downto 0);
    signal ctrl_wr_ack          : std_logic;
    signal ctrl_rd_req          : std_logic;
    signal ctrl_rd_addr         : std_logic_vector(24 downto 0);
    signal ctrl_rd_data         : std_logic_vector(15 downto 0);
    signal ctrl_rd_valid        : std_logic;
    signal ctrl_rd_ack          : std_logic;

    signal iface_rst_n          : std_logic;
    -- Fix 2: released once BIST has completed (pass="10" or fail="11")
    -- iface_rst_n must not be held for the entire bist_mode="01" duration
    -- because sdram_interface needs to start as soon as SDRAM is ready.
    signal bist_done            : std_logic := '1';

    type bist_state_t is (
        ST_WAIT_INIT,
        ST_WR_REQ,
        ST_WR_HOLD,
        ST_RD_REQ,
        ST_RD_WAIT
    );

    signal bist_state    : bist_state_t := ST_WAIT_INIT;
    signal bist_addr     : unsigned(9 downto 0) := (others => '0');
    signal bist_mode     : std_logic_vector(1 downto 0) := "00";  -- DEFAULT: BIST disabled
    signal bist_ran      : std_logic := '1';
    signal init_cnt      : unsigned(15 downto 0) := (others => '0');
    signal pass_cnt      : unsigned(25 downto 0) := (others => '0');
    signal bist_state_code : unsigned(2 downto 0) := (others => '0');
    signal fail_addr     : unsigned(9 downto 0) := (others => '0');
    signal fail_exp      : std_logic_vector(15 downto 0) := (others => '0');
    signal fail_got      : std_logic_vector(15 downto 0) := (others => '0');
    signal fail_latched  : std_logic := '0';
    signal disp_cnt      : unsigned(25 downto 0) := (others => '0');
    signal disp_phase    : unsigned(1 downto 0) := (others => '0');

    function bist_pattern(a : unsigned(9 downto 0)) return std_logic_vector is
        variable w : unsigned(15 downto 0);
    begin
        w := resize(a, 16) xor x"A5A5";
        return std_logic_vector(w);
    end function;

begin

    -- =========================================================================
    -- 2-FF synchroniser: frame_done PCLK -> clk_130m (75 MHz)
    -- -------------------------------------------------------------------------
    p_frame_sync : process(clk_130m, rst_n)
    begin
        if rst_n = '0' then
            frame_done_s1 <= '0';
            frame_done_s2 <= '0';
            vga_vsync_s1  <= '1';
            vga_vsync_s2  <= '1';
        elsif rising_edge(clk_130m) then
            frame_done_s1 <= frame_done_async;
            frame_done_s2 <= frame_done_s1;
            vga_vsync_s1  <= vga_vsync_async;
            vga_vsync_s2  <= vga_vsync_s1;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- SDRAM interface (arbitrator)
    -- -------------------------------------------------------------------------
    u_iface : sdram_interface
        port map (
            clk              => clk_130m,
            rst_n            => iface_rst_n,
            cam_fifo_rd_en   => cam_fifo_rd_en,
            cam_fifo_rd_data => cam_fifo_rd_data,
            cam_fifo_empty   => cam_fifo_empty,
            cam_fifo_rd_usedw=> cam_fifo_rd_usedw,
            vga_fifo_wr_en   => vga_fifo_wr_en,
            vga_fifo_wr_data => vga_fifo_wr_data,
            vga_fifo_full    => vga_fifo_full,
            sdram_wr_req     => iface_wr_req,
            sdram_wr_addr    => iface_wr_addr,
            sdram_wr_data    => iface_wr_data,
            sdram_wr_ack     => iface_wr_ack,
            sdram_rd_req     => iface_rd_req,
            sdram_rd_addr    => iface_rd_addr,
            sdram_rd_data    => iface_rd_data,
            sdram_rd_valid   => iface_rd_valid,
            sdram_rd_ack     => iface_rd_ack,
            frame_done_sync  => frame_done_s2,
            vga_vsync_sync   => vga_vsync_s2,
            debug_cfr01_dbg  => debug_cfr01_dbg,
            debug_cfr23_dbg  => debug_cfr23_dbg,
            debug_cfr45_dbg  => debug_cfr45_dbg,
            debug_cfr67_dbg  => debug_cfr67_dbg,
            debug_vgr01_dbg  => debug_vgr01_dbg,
            debug_vgr23_dbg  => debug_vgr23_dbg,
            debug_vgr45_dbg  => debug_vgr45_dbg,
            debug_vgr67_dbg  => debug_vgr67_dbg,
            debug_vgl0_dbg   => debug_vgl0_dbg,
            debug_vgl60_dbg  => debug_vgl60_dbg,
            debug_vgl120_dbg => debug_vgl120_dbg,
            debug_vgl180_dbg => debug_vgl180_dbg,
            debug_sch_dbg    => debug_sch_dbg
        );

    -- -------------------------------------------------------------------------
    -- SDRAM controller (low-level command FSM)
    -- sdram_clk output is NOT connected here; DRAM_CLK comes from PLL c3
    -- directly in stream_top to preserve phase relationship
    -- -------------------------------------------------------------------------
    u_ctrl : sdram_controller
        port map (
            clk         => clk_130m,
            rst_n       => rst_n,
            wr_req      => ctrl_wr_req,
            wr_addr     => ctrl_wr_addr,
            wr_data     => ctrl_wr_data,
            wr_ack      => ctrl_wr_ack,
            rd_req      => ctrl_rd_req,
            rd_addr     => ctrl_rd_addr,
            rd_data     => ctrl_rd_data,
            rd_valid    => ctrl_rd_valid,
            rd_ack      => ctrl_rd_ack,
            sdram_clk   => open,
            sdram_cke   => sdram_cke,
            sdram_cs_n  => sdram_cs_n,
            sdram_ras_n => sdram_ras_n,
            sdram_cas_n => sdram_cas_n,
            sdram_we_n  => sdram_we_n,
            sdram_ba    => sdram_ba,
            sdram_addr  => sdram_addr,
            sdram_dqm   => sdram_dqm,
            sdram_dq    => sdram_dq
        );

    p_bist : process(clk_130m, rst_n)
        constant INIT_WAIT_MAX : unsigned(15 downto 0) := to_unsigned(30000, 16);
        constant PASS_HOLD_MAX : unsigned(25 downto 0) := to_unsigned(50_000_000 - 1, 26);
    begin
        if rst_n = '0' then
            bist_state <= ST_WAIT_INIT;
            bist_addr  <= (others => '0');
            bist_mode  <= "00";  -- DEFAULT: BIST disabled on power-up
            bist_ran   <= '1';   -- FIX: prevent BIST from ever starting
            init_cnt   <= (others => '0');
            pass_cnt   <= (others => '0');
            fail_addr  <= (others => '0');
            fail_exp   <= (others => '0');
            fail_got   <= (others => '0');
            fail_latched <= '0';
            disp_cnt   <= (others => '0');
            disp_phase <= (others => '0');
            bist_done  <= '1';   -- Release sdram_interface immediately (BIST skipped)
        elsif rising_edge(clk_130m) then
            if bist_release_n = '0' then
                -- KEY(1) is pressed (active low) -> skip BIST and go directly to normal mode
                bist_state <= ST_WAIT_INIT;
                bist_addr  <= (others => '0');
                bist_mode  <= "00";
                bist_ran   <= '1';
                init_cnt   <= (others => '0');
                pass_cnt   <= (others => '0');
                fail_addr  <= (others => '0');
                fail_exp   <= (others => '0');
                fail_got   <= (others => '0');
                fail_latched <= '0';
                disp_cnt   <= (others => '0');
                disp_phase <= (others => '0');
                bist_done  <= '1';
            else
            if bist_ran = '0' and bist_mode = "00" then
                bist_mode <= "01";
                bist_done <= '0';
                init_cnt  <= (others => '0');
                pass_cnt  <= (others => '0');
                bist_addr <= (others => '0');
                fail_latched <= '0';
                bist_state <= ST_WAIT_INIT;
                bist_ran <= '1';
            end if;
            if bist_mode = "11" then
                if disp_cnt = to_unsigned(50_000_000 - 1, disp_cnt'length) then
                    disp_cnt <= (others => '0');
                    disp_phase <= disp_phase + 1;
                else
                    disp_cnt <= disp_cnt + 1;
                end if;
            else
                disp_cnt <= (others => '0');
                disp_phase <= (others => '0');
            end if;

            case bist_state is
                when ST_WAIT_INIT => bist_state_code <= to_unsigned(0, 3);
                when ST_WR_REQ    => bist_state_code <= to_unsigned(1, 3);
                when ST_WR_HOLD   => bist_state_code <= to_unsigned(2, 3);
                when ST_RD_REQ    => bist_state_code <= to_unsigned(3, 3);
                when ST_RD_WAIT   => bist_state_code <= to_unsigned(4, 3);
                when others       => bist_state_code <= to_unsigned(7, 3);
            end case;

            if bist_mode = "10" then
                bist_done <= '1';   -- Fix 2: BIST passed, release sdram_interface
                if pass_cnt = PASS_HOLD_MAX then
                    bist_mode <= "00";
                    pass_cnt  <= (others => '0');
                else
                    pass_cnt <= pass_cnt + 1;
                end if;
            elsif bist_mode = "11" then
                bist_done <= '1';   -- Fix 2: BIST failed, still release sdram_interface
            end if;

            case bist_state is
                when ST_WAIT_INIT =>
                    if bist_mode /= "01" then
                        null;
                    else
                        if init_cnt = INIT_WAIT_MAX then
                            init_cnt   <= (others => '0');
                            bist_addr  <= (others => '0');
                            bist_state <= ST_WR_REQ;
                        else
                            init_cnt <= init_cnt + 1;
                        end if;
                    end if;

                when ST_WR_REQ =>
                    if ctrl_wr_ack = '1' then
                        bist_state <= ST_WR_HOLD;
                    end if;

                when ST_WR_HOLD =>
                    if bist_addr = to_unsigned(1023, bist_addr'length) then
                        bist_addr  <= (others => '0');
                        bist_state <= ST_RD_REQ;
                    else
                        bist_addr  <= bist_addr + 1;
                        bist_state <= ST_WR_REQ;
                    end if;

                when ST_RD_REQ =>
                    if ctrl_rd_ack = '1' then
                        bist_state <= ST_RD_WAIT;
                    end if;

                when ST_RD_WAIT =>
                    if ctrl_rd_valid = '1' then
                        if ctrl_rd_data /= bist_pattern(bist_addr) then
                            if fail_latched = '0' then
                                fail_addr <= bist_addr;
                                fail_exp  <= bist_pattern(bist_addr);
                                fail_got  <= ctrl_rd_data;
                                fail_latched <= '1';
                            end if;
                            bist_mode <= "11";
                            bist_state <= ST_WAIT_INIT;
                        else
                            if bist_addr = to_unsigned(1023, bist_addr'length) then
                                bist_mode <= "10";
                                pass_cnt  <= (others => '0');
                                bist_state <= ST_WAIT_INIT;
                            else
                                bist_addr  <= bist_addr + 1;
                                bist_state <= ST_RD_REQ;
                            end if;
                        end if;
                    end if;

                when others =>
                    bist_state <= ST_WAIT_INIT;
            end case;
            end if;
        end if;
    end process;

    test_mode <= bist_mode;
    -- Fix 2: release sdram_interface once BIST is done (pass or fail),
    -- not held until bist_mode transitions all the way to "00".
    iface_rst_n <= rst_n when bist_done = '1' else '0';
    test_leds <= std_logic_vector(fail_addr) when (bist_mode = "11" and disp_phase = "00") else
                 fail_exp(9 downto 0)        when (bist_mode = "11" and disp_phase = "01") else
                 fail_got(9 downto 0)        when (bist_mode = "11" and disp_phase = "10") else
                 (bist_mode & std_logic_vector(bist_state_code) & "00000");

    ctrl_wr_req  <= '1' when (bist_mode = "01" and bist_state = ST_WR_REQ) else iface_wr_req;
    ctrl_wr_addr <= std_logic_vector(resize(bist_addr, 25)) when (bist_mode = "01") else iface_wr_addr;
    ctrl_wr_data <= bist_pattern(bist_addr) & bist_pattern(bist_addr) & bist_pattern(bist_addr) & bist_pattern(bist_addr) & bist_pattern(bist_addr) & bist_pattern(bist_addr) & bist_pattern(bist_addr) & bist_pattern(bist_addr) when (bist_mode = "01") else iface_wr_data;

    ctrl_rd_req  <= '1' when (bist_mode = "01" and bist_state = ST_RD_REQ) else iface_rd_req;
    ctrl_rd_addr <= std_logic_vector(resize(bist_addr, 25)) when (bist_mode = "01" and bist_state = ST_RD_REQ) else iface_rd_addr;

    iface_wr_ack    <= ctrl_wr_ack when (bist_mode /= "01") else '0';
    iface_rd_ack    <= ctrl_rd_ack when (bist_mode /= "01") else '0';
    iface_rd_valid  <= ctrl_rd_valid when (bist_mode /= "01") else '0';
    iface_rd_data   <= ctrl_rd_data when (bist_mode /= "01") else (others => '0');

end architecture rtl;
