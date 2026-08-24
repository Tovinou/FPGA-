-- =============================================================================
-- sdram_interface.vhd  (CORRECTED v3)
-- Arbitrates camera-FIFO writes and SDRAM reads to the VGA FIFO.
--
-- BUG FIXES vs previous version:
--   BUG1: rd_ptr was advancing by 1 per burst instead of 8.
--         Fixed: rd_ptr <= rd_ptr + 8 at end of read burst.
--   BUG2: vga_fifo_wr_en was combinatorial and went '0' on the same
--         clock edge the state transitioned away from ST_WAIT_RD_DATA,
--         dropping every 8th pixel word.
--         Fixed: vga_fifo_wr_en driven by registered signal inside FSM.
--   BUG6: read_bank snapped to write_bank on vsync — wrong bank after
--         frame_done toggles write_bank (completed frame is in NOT write_bank).
--         Fixed: read_bank <= not write_bank when new_frame_ready; vsync-only swap.
--   BUG7: camera FIFO read data was consumed in the same cycle as rd_en,
--         but the FIFO is configured with showahead OFF. That duplicates/shifts
--         words at the SDRAM write ingress.
--         Fixed: issue cam_fifo_rd_en first, then capture cam_fifo_rd_data
--         on the following cycle via cam_rd_pending.
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sdram_interface is
    port (
        clk              : in    std_logic;   -- 100 MHz
        rst_n            : in    std_logic;

        -- Camera FIFO (showahead, 100 MHz domain)
        cam_fifo_rd_en   : out   std_logic;
        cam_fifo_rd_data : in    std_logic_vector(15 downto 0);
        cam_fifo_empty   : in    std_logic;
        cam_fifo_rd_usedw: in    std_logic_vector(8 downto 0);

        -- VGA FIFO write side (100 MHz domain)
        vga_fifo_wr_en   : out   std_logic;
        vga_fifo_wr_data : out   std_logic_vector(15 downto 0);
        vga_fifo_full    : in    std_logic;

        -- SDRAM controller write interface
        sdram_wr_req     : out   std_logic;
        sdram_wr_addr    : out   std_logic_vector(24 downto 0);
        sdram_wr_data    : out   std_logic_vector(127 downto 0);
        sdram_wr_ack     : in    std_logic;

        -- SDRAM controller read interface
        sdram_rd_req     : out   std_logic;
        sdram_rd_addr    : out   std_logic_vector(24 downto 0);
        sdram_rd_data    : in    std_logic_vector(15 downto 0);
        sdram_rd_valid   : in    std_logic;
        sdram_rd_ack     : in    std_logic;

        -- Synchronised control signals (already in 100 MHz domain)
        frame_done_sync  : in    std_logic;
        vga_vsync_sync   : in    std_logic;

        -- Internal debug reference samples
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
end entity sdram_interface;

architecture rtl of sdram_interface is

    -- Frame geometry
    constant FRAME_PIXELS : unsigned(24 downto 0) := to_unsigned(76800, 25); -- 320*240
    constant BANK_WORDS   : unsigned(24 downto 0) := to_unsigned(76800, 25);
    constant LINE_PIXELS  : unsigned(24 downto 0) := to_unsigned(320, 25);

    -- Double-buffer bank control
    signal write_bank       : std_logic := '0';
    signal read_bank        : std_logic := '1';
    signal wr_base          : unsigned(24 downto 0);
    signal rd_base          : unsigned(24 downto 0);

    -- BUG6 FIX: only swap read_bank when a full new frame is ready
    signal new_frame_ready  : std_logic := '0';
    signal read_frame_valid : std_logic := '0';

    -- Write state
    signal wr_ptr          : unsigned(24 downto 0) := (others => '0');
    signal wr_burst_cnt    : unsigned(2 downto 0)  := (others => '0');
    signal wr_data_latch   : std_logic_vector(127 downto 0) := (others => '0');
    signal wr_addr_latch   : std_logic_vector(24 downto 0)  := (others => '0');

    -- Read state
    signal rd_ptr          : unsigned(24 downto 0) := (others => '0');
    signal rd_burst_cnt    : unsigned(2 downto 0)  := (others => '0');

    -- Edge detectors
    signal frame_done_d    : std_logic := '0';
    signal vsync_d         : std_logic := '1';

    -- FSM
    type arb_state_t is (
        ST_FILL_CAM,
        ST_ISSUE_WR,
        ST_WAIT_WR_ACK,
        ST_ISSUE_RD,
        ST_WAIT_RD_ACK,
        ST_WAIT_RD_DATA
    );
    signal state : arb_state_t := ST_FILL_CAM;

    signal wr_req_int      : std_logic := '0';
    signal rd_req_int      : std_logic := '0';
    signal cam_rd_int      : std_logic := '0';
    signal cam_rd_pending  : std_logic := '0';

    -- Capture SDRAM read data, then push it into the VGA FIFO on the next cycle.
    signal vga_wr_en_int      : std_logic := '0';
    signal vga_wr_data_int    : std_logic_vector(15 downto 0) := (others => '0');
    signal vga_wr_pending     : std_logic := '0';
    signal vga_wr_data_hold   : std_logic_vector(15 downto 0) := (others => '0');

    signal debug_vgl0_int   : std_logic_vector(31 downto 0) := (others => '0');
    signal debug_vgl60_int  : std_logic_vector(31 downto 0) := (others => '0');
    signal debug_vgl120_int : std_logic_vector(31 downto 0) := (others => '0');
    signal debug_vgl180_int : std_logic_vector(31 downto 0) := (others => '0');

    -- Internal debug references sampled at the true pipeline stages
    signal debug_cfr01_int : std_logic_vector(31 downto 0) := (others => '0');
    signal debug_cfr23_int : std_logic_vector(31 downto 0) := (others => '0');
    signal debug_cfr45_int : std_logic_vector(31 downto 0) := (others => '0');
    signal debug_cfr67_int : std_logic_vector(31 downto 0) := (others => '0');
    signal debug_vgr01_int : std_logic_vector(31 downto 0) := (others => '0');
    signal debug_vgr23_int : std_logic_vector(31 downto 0) := (others => '0');
    signal debug_vgr45_int : std_logic_vector(31 downto 0) := (others => '0');
    signal debug_vgr67_int : std_logic_vector(31 downto 0) := (others => '0');
    signal debug_cfr_arm   : std_logic := '0';
    signal debug_vgr_arm   : std_logic := '0';
    signal debug_cfr_idx   : unsigned(8 downto 0) := (others => '0');
    signal debug_vgr_idx   : unsigned(8 downto 0) := (others => '0');

    constant CAM_FIFO_HIGH_WATER : unsigned(8 downto 0) := to_unsigned(384, 9);

begin
    debug_sch_dbg <= new_frame_ready &
                     read_frame_valid &
                     vga_vsync_sync &
                     vga_fifo_full &
                     cam_fifo_empty &
                     frame_done_sync &
                     rd_req_int &
                     vga_wr_pending &
                     std_logic_vector(to_unsigned(arb_state_t'pos(state), 4)) &
                     std_logic_vector(rd_ptr(19 downto 0));
    debug_vgl0_dbg   <= debug_vgl0_int;
    debug_vgl60_dbg  <= debug_vgl60_int;
    debug_vgl120_dbg <= debug_vgl120_int;
    debug_vgl180_dbg <= debug_vgl180_int;

    wr_base <= (others => '0') when write_bank = '0' else BANK_WORDS;
    rd_base <= (others => '0') when read_bank  = '0' else BANK_WORDS;

    sdram_wr_req  <= wr_req_int;
    sdram_rd_req  <= rd_req_int;
    sdram_wr_addr <= wr_addr_latch;
    sdram_rd_addr <= std_logic_vector(rd_base + rd_ptr);
    sdram_wr_data <= wr_data_latch;

    cam_fifo_rd_en   <= cam_rd_int;

    -- BUG2 FIX: expose registered signals (not combinatorial state-gated)
    vga_fifo_wr_en   <= vga_wr_en_int;
    vga_fifo_wr_data <= vga_wr_data_int;

    debug_cfr01_dbg <= debug_cfr01_int;
    debug_cfr23_dbg <= debug_cfr23_int;
    debug_cfr45_dbg <= debug_cfr45_int;
    debug_cfr67_dbg <= debug_cfr67_int;
    debug_vgr01_dbg <= debug_vgr01_int;
    debug_vgr23_dbg <= debug_vgr23_int;
    debug_vgr45_dbg <= debug_vgr45_int;
    debug_vgr67_dbg <= debug_vgr67_int;

    -- =========================================================================
    -- Main arbitration FSM
    -- =========================================================================
    p_arb : process(clk, rst_n)
    begin
        if rst_n = '0' then
            state           <= ST_FILL_CAM;
            wr_req_int      <= '0';
            rd_req_int      <= '0';
            cam_rd_int      <= '0';
            cam_rd_pending  <= '0';
            vga_wr_en_int   <= '0';
            vga_wr_data_int <= (others => '0');
            vga_wr_pending  <= '0';
            vga_wr_data_hold <= (others => '0');
            wr_ptr          <= (others => '0');
            rd_ptr          <= (others => '0');
            wr_burst_cnt    <= (others => '0');
            rd_burst_cnt    <= (others => '0');
            wr_data_latch   <= (others => '0');
            wr_addr_latch   <= (others => '0');
            write_bank      <= '0';
            read_bank       <= '1';
            new_frame_ready <= '0';
            read_frame_valid <= '0';
            frame_done_d    <= '0';
            vsync_d         <= '1';
            debug_cfr01_int <= (others => '0');
            debug_cfr23_int <= (others => '0');
            debug_cfr45_int <= (others => '0');
            debug_cfr67_int <= (others => '0');
            debug_vgr01_int <= (others => '0');
            debug_vgr23_int <= (others => '0');
            debug_vgr45_int <= (others => '0');
            debug_vgr67_int <= (others => '0');
            debug_cfr_arm   <= '0';
            debug_vgr_arm   <= '0';
            debug_cfr_idx   <= (others => '0');
            debug_vgr_idx   <= (others => '0');
            debug_vgl0_int   <= (others => '0');
            debug_vgl60_int  <= (others => '0');
            debug_vgl120_int <= (others => '0');
            debug_vgl180_int <= (others => '0');

        elsif rising_edge(clk) then

            -- Default deassert all strobes each cycle
            wr_req_int    <= '0';
            rd_req_int    <= '0';
            cam_rd_int    <= '0';
            vga_wr_en_int <= '0';   -- BUG2 FIX: default deassert every cycle

            if vga_wr_pending = '1' then
                vga_wr_en_int   <= '1';
                vga_wr_data_int <= vga_wr_data_hold;
                vga_wr_pending  <= '0';
            end if;

            -- Edge detectors
            vsync_d      <= vga_vsync_sync;
            frame_done_d <= frame_done_sync;

            -- ---------------------------------------------------------------
            -- Camera frame done: advance write bank, reset write pointer
            -- Set new_frame_ready so VGA knows a complete frame is waiting
            -- ---------------------------------------------------------------
            if frame_done_sync = '1' and frame_done_d = '0' then
                write_bank      <= not write_bank;
                wr_ptr          <= (others => '0');
                wr_burst_cnt    <= (others => '0');
                cam_rd_pending  <= '0';
                vga_wr_pending  <= '0';
                new_frame_ready <= '1';     -- BUG6 FIX: flag new frame
                debug_cfr01_int <= (others => '0');
                debug_cfr23_int <= (others => '0');
                debug_cfr45_int <= (others => '0');
                debug_cfr67_int <= (others => '0');
                debug_cfr_arm   <= '1';
                debug_cfr_idx   <= (others => '0');
                -- Abort any in-progress write so we start fresh next frame
                if state = ST_ISSUE_WR or state = ST_WAIT_WR_ACK then
                    state <= ST_FILL_CAM;
                end if;
            end if;

            -- ---------------------------------------------------------------
            -- VGA vsync falling edge: reset read pointer
            -- BUG6 FIX: only swap read_bank when a new frame is ready
            -- ---------------------------------------------------------------
            if vga_vsync_sync = '0' and vsync_d = '1' then
                rd_ptr       <= (others => '0');
                rd_burst_cnt <= (others => '0');
                vga_wr_pending <= '0';
                if new_frame_ready = '1' then
                    read_bank       <= not write_bank;  -- completed frame is in opposite bank
                    new_frame_ready <= '0';
                    read_frame_valid <= '1';
                end if;
                debug_vgr01_int <= (others => '0');
                debug_vgr23_int <= (others => '0');
                debug_vgr45_int <= (others => '0');
                debug_vgr67_int <= (others => '0');
                debug_vgr_arm   <= '1';
                debug_vgr_idx   <= (others => '0');
                debug_vgl0_int   <= (others => '0');
                debug_vgl60_int  <= (others => '0');
                debug_vgl120_int <= (others => '0');
                debug_vgl180_int <= (others => '0');
                -- Abort any in-progress read
                if state = ST_WAIT_RD_DATA or state = ST_WAIT_RD_ACK then
                    state <= ST_FILL_CAM;
                end if;
            end if;

            case state is

                -- =============================================================
                -- FILL: accumulate 8 pixels from camera FIFO into wr_data_latch.
                -- Use a conservative 2-cycle read sequence: pulse rd_en on one
                -- cycle, then consume q on the next. This avoids overlapping a
                -- new rd_en with the capture of the previous q value.
                -- =============================================================
                when ST_FILL_CAM =>
                    if cam_rd_pending = '1' then
                        if debug_cfr_arm = '1' then
                            case to_integer(debug_cfr_idx) is
                                when 20  => debug_cfr01_int(31 downto 16) <= cam_fifo_rd_data;
                                when 60  => debug_cfr01_int(15 downto 0)  <= cam_fifo_rd_data;
                                when 100 => debug_cfr23_int(31 downto 16) <= cam_fifo_rd_data;
                                when 140 => debug_cfr23_int(15 downto 0)  <= cam_fifo_rd_data;
                                when 180 => debug_cfr45_int(31 downto 16) <= cam_fifo_rd_data;
                                when 220 => debug_cfr45_int(15 downto 0)  <= cam_fifo_rd_data;
                                when 260 => debug_cfr67_int(31 downto 16) <= cam_fifo_rd_data;
                                when 300 => debug_cfr67_int(15 downto 0)  <= cam_fifo_rd_data;
                                when others => null;
                            end case;

                            if debug_cfr_idx = to_unsigned(300, debug_cfr_idx'length) then
                                debug_cfr_arm <= '0';
                            else
                                debug_cfr_idx <= debug_cfr_idx + 1;
                            end if;
                        end if;

                        -- Pack pixels LSB-first so the controller writes P0 first
                        wr_data_latch <= cam_fifo_rd_data & wr_data_latch(127 downto 16);

                        -- Latch SDRAM write address once at start of burst
                        if wr_burst_cnt = 0 then
                            wr_addr_latch <= std_logic_vector(wr_base + wr_ptr);
                        end if;

                        if wr_burst_cnt = 7 then
                            cam_rd_pending <= '0';
                            wr_burst_cnt <= (others => '0');
                            -- Advance write pointer by burst length
                            if wr_ptr + 8 < FRAME_PIXELS then
                                wr_ptr <= wr_ptr + 8;
                            end if;
                            state <= ST_ISSUE_WR;
                        else
                            cam_rd_pending <= '0';
                            wr_burst_cnt <= wr_burst_cnt + 1;
                        end if;

				   -- elsif read_frame_valid = '1' and vga_fifo_full = '0' and
						--rd_ptr < FRAME_PIXELS and unsigned(cam_fifo_rd_usedw) < CAM_FIFO_HIGH_WATER then
                    -- The VGA FIFO is held in reset throughout the active-low
                    -- VSYNC pulse.  Do not begin the next SDRAM read stream
                    -- until that reset has released, otherwise its leading
                    -- pixels are discarded and every displayed line is offset.
                    elsif read_frame_valid = '1' and vga_vsync_sync = '1' and
                          vga_fifo_full = '0' and rd_ptr < FRAME_PIXELS then
											
                   -- elsif read_frame_valid = '1' and vga_vsync_sync = '1' and vga_fifo_full = '0' and
                         -- rd_ptr < FRAME_PIXELS and unsigned(cam_fifo_rd_usedw) < CAM_FIFO_HIGH_WATER then
                        -- Keep the VGA FIFO fed unless the camera FIFO is getting too full.
                        state <= ST_ISSUE_RD;
                    elsif cam_fifo_empty = '0' then
                        cam_rd_int     <= '1';
                        cam_rd_pending <= '1';
                    else
                        null;
                    end if;

                -- =============================================================
                -- ISSUE WRITE
                -- =============================================================
                when ST_ISSUE_WR =>
                    wr_req_int <= '1';
                    state      <= ST_WAIT_WR_ACK;

                when ST_WAIT_WR_ACK =>
                    wr_req_int <= '1';
                    if sdram_wr_ack = '1' then
                        -- After a write burst, do a read burst if VGA needs data
                        if read_frame_valid = '1' and vga_vsync_sync = '1' and vga_fifo_full = '0' and rd_ptr < FRAME_PIXELS then
                            state <= ST_ISSUE_RD;
                        else
                            state <= ST_FILL_CAM;
                        end if;
                    end if;

                -- =============================================================
                -- ISSUE READ
                -- =============================================================
                when ST_ISSUE_RD =>
                    rd_req_int <= '1';
                    state      <= ST_WAIT_RD_ACK;

                when ST_WAIT_RD_ACK =>
                    rd_req_int <= '1';
                    if sdram_rd_ack = '1' then
                        state <= ST_WAIT_RD_DATA;
                    end if;

                -- =============================================================
                -- WAIT READ DATA: collect 8 rd_valid pulses
                -- BUG2 FIX: vga_wr_en_int set INSIDE FSM (registered),
                --           so it is valid on the same cycle sdram_rd_valid fires.
                --           The FIFO captures on the next rising edge, which is
                --           correct because sdram_rd_data (rd_data_reg) is stable.
                -- BUG1 FIX: rd_ptr advances by 8 after full burst (not 1).
                -- =============================================================
                when ST_WAIT_RD_DATA =>
                    if sdram_rd_valid = '1' then
                        if (rd_ptr + resize(rd_burst_cnt, rd_ptr'length)) = to_unsigned(20, 25) then
                            debug_vgl0_int(31 downto 16) <= sdram_rd_data;
                        elsif (rd_ptr + resize(rd_burst_cnt, rd_ptr'length)) = to_unsigned(180, 25) then
                            debug_vgl0_int(15 downto 0) <= sdram_rd_data;
                        elsif (rd_ptr + resize(rd_burst_cnt, rd_ptr'length)) = (to_unsigned(60, 25) * LINE_PIXELS + to_unsigned(20, 25)) then
                            debug_vgl60_int(31 downto 16) <= sdram_rd_data;
                        elsif (rd_ptr + resize(rd_burst_cnt, rd_ptr'length)) = (to_unsigned(60, 25) * LINE_PIXELS + to_unsigned(180, 25)) then
                            debug_vgl60_int(15 downto 0) <= sdram_rd_data;
                        elsif (rd_ptr + resize(rd_burst_cnt, rd_ptr'length)) = (to_unsigned(120, 25) * LINE_PIXELS + to_unsigned(20, 25)) then
                            debug_vgl120_int(31 downto 16) <= sdram_rd_data;
                        elsif (rd_ptr + resize(rd_burst_cnt, rd_ptr'length)) = (to_unsigned(120, 25) * LINE_PIXELS + to_unsigned(180, 25)) then
                            debug_vgl120_int(15 downto 0) <= sdram_rd_data;
                        elsif (rd_ptr + resize(rd_burst_cnt, rd_ptr'length)) = (to_unsigned(180, 25) * LINE_PIXELS + to_unsigned(20, 25)) then
                            debug_vgl180_int(31 downto 16) <= sdram_rd_data;
                        elsif (rd_ptr + resize(rd_burst_cnt, rd_ptr'length)) = (to_unsigned(180, 25) * LINE_PIXELS + to_unsigned(180, 25)) then
                            debug_vgl180_int(15 downto 0) <= sdram_rd_data;
                        end if;
                        if debug_vgr_arm = '1' then
                            case to_integer(debug_vgr_idx) is
                                when 20  => debug_vgr01_int(31 downto 16) <= sdram_rd_data;
                                when 60  => debug_vgr01_int(15 downto 0)  <= sdram_rd_data;
                                when 100 => debug_vgr23_int(31 downto 16) <= sdram_rd_data;
                                when 140 => debug_vgr23_int(15 downto 0)  <= sdram_rd_data;
                                when 180 => debug_vgr45_int(31 downto 16) <= sdram_rd_data;
                                when 220 => debug_vgr45_int(15 downto 0)  <= sdram_rd_data;
                                when 260 => debug_vgr67_int(31 downto 16) <= sdram_rd_data;
                                when 300 => debug_vgr67_int(15 downto 0)  <= sdram_rd_data;
                                when others => null;
                            end case;

                            if debug_vgr_idx = to_unsigned(300, debug_vgr_idx'length) then
                                debug_vgr_arm <= '0';
                            else
                                debug_vgr_idx <= debug_vgr_idx + 1;
                            end if;
                        end if;

                        vga_wr_data_hold <= sdram_rd_data;
                        vga_wr_pending   <= '1';

                        if rd_burst_cnt = 7 then
                            rd_burst_cnt <= (others => '0');
                            -- BUG1 FIX: advance rd_ptr by burst length (8), not 1
                            if rd_ptr >= FRAME_PIXELS - 8 then
                                rd_ptr <= (others => '0');
                            else
                                rd_ptr <= rd_ptr + 8;
                            end if;
                            state <= ST_FILL_CAM;
                        else
                            rd_burst_cnt <= rd_burst_cnt + 1;
                        end if;
                    end if;

                when others =>
                    state <= ST_FILL_CAM;

            end case;

        end if;
    end process;

end architecture rtl;
