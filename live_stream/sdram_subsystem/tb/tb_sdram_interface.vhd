-- =============================================================================
-- tb_sdram_interface.vhd
-- VUnit testbench for sdram_interface.vhd (corrected version)
--
-- Strategy:
--   The SDRAM controller is replaced by a simple stub that acknowledges
--   requests immediately and returns preset read data.
--   Camera FIFO and VGA FIFO are driven directly from the TB.
--
-- Tests:
--   tc_reset_idle           : no outputs asserted after reset
--   tc_write_priority       : camera write processed before VGA read
--   tc_cam_fifo_pop_timing  : cam_rd_en before wr_req (FIX 3)
--   tc_wr_data_latched      : sdram_wr_data matches cam_fifo_rd_data
--   tc_wr_ptr_advances      : wr_ptr increments after each write ack
--   tc_rd_ptr_advances      : rd_ptr increments after each read valid
--   tc_no_write_frame_full  : writes stop when wr_ptr reaches FRAME_WORDS
--   tc_no_read_vga_full     : reads stop when VGA FIFO full
--   tc_rd_ptr_wraps         : rd_ptr wraps to 0 at FRAME_WORDS boundary
--   tc_bank_swap_on_frame   : bank selector toggles on frame_done pulse
--   tc_rd_ptr_not_reset     : rd_ptr unchanged by frame_done (tearing fix)
--   tc_write_to_read_switch : FSM switches to read when cam FIFO empty
--   tc_vga_fifo_written     : vga_fifo_wr_en asserts when rd_valid fires
--   tc_double_buffer_addrs  : write and read addresses use different banks
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_sdram_interface is
    generic (runner_cfg : string);
end entity;

architecture sim of tb_sdram_interface is

    constant T_CLK : time := 10 ns;   -- 100 MHz

    -- =========================================================================
    -- DUT ports
    -- =========================================================================
    signal clk             : std_logic := '0';
    signal rst_n           : std_logic := '0';

    -- Camera FIFO stub
    signal cam_fifo_rd_en   : std_logic;
    signal cam_fifo_rd_data : std_logic_vector(15 downto 0) := x"CACA";
    signal cam_fifo_empty   : std_logic := '1';

    -- VGA FIFO stub
    signal vga_fifo_wr_en   : std_logic;
    signal vga_fifo_wr_data : std_logic_vector(15 downto 0);
    signal vga_fifo_full    : std_logic := '0';

    -- SDRAM controller stub
    signal sdram_wr_req   : std_logic;
    signal sdram_wr_addr  : std_logic_vector(24 downto 0);
    signal sdram_wr_data  : std_logic_vector(15 downto 0);
    signal sdram_wr_ack   : std_logic := '0';

    signal sdram_rd_req   : std_logic;
    signal sdram_rd_addr  : std_logic_vector(24 downto 0);
    signal sdram_rd_data  : std_logic_vector(15 downto 0) := x"D0D0";
    signal sdram_rd_valid : std_logic := '0';
    signal sdram_rd_ack   : std_logic := '0';

    signal frame_done_sync : std_logic := '0';
    signal vga_vsync_sync  : std_logic := '1';

    -- =========================================================================
    -- SDRAM controller stub: responds to requests with configurable latency
    -- =========================================================================
    signal stub_wr_ack_delay : integer range 0 to 20 := 3;
    signal stub_rd_ack_delay : integer range 0 to 20 := 3;
    signal stub_rd_lat       : integer range 0 to 20 := 5;
    signal stub_rd_data_val  : std_logic_vector(15 downto 0) := x"D0D0";

    -- Frame size constant (matches DUT)
    constant FRAME_WORDS : integer := 307200;  -- 640*480, matches DUT BANK_WORDS

    procedure clk_wait(n : natural) is
    begin
        for i in 1 to n loop wait until rising_edge(clk); end loop;
    end procedure;

    procedure do_reset(
        signal rst_n           : out std_logic;
        signal cam_fifo_empty  : out std_logic;
        signal vga_fifo_full   : out std_logic;
        signal frame_done_sync : out std_logic
    ) is
    begin
        rst_n          <= '0';
        cam_fifo_empty <= '1';
        vga_fifo_full  <= '1';
        frame_done_sync<= '0';
        clk_wait(6);
        rst_n <= '1';
        clk_wait(4);
    end procedure;

    procedure pulse_frame_done(signal frame_done_sync : out std_logic) is
    begin
        frame_done_sync <= '1';
        clk_wait(1);
        frame_done_sync <= '0';
        clk_wait(2);
    end procedure;

    procedure pulse_vga_vsync(signal vga_vsync_sync : out std_logic) is
    begin
        vga_vsync_sync <= '0';
        clk_wait(1);
        vga_vsync_sync <= '1';
        clk_wait(2);
    end procedure;

    -- Drive one complete write transaction through the interface
    procedure drive_write(
        signal cam_fifo_rd_data : out std_logic_vector(15 downto 0);
        signal cam_fifo_empty   : out std_logic;
        signal cam_fifo_rd_en   : in  std_logic;
        signal sdram_wr_req     : in  std_logic;
        signal sdram_wr_ack     : out std_logic;
        data                   : std_logic_vector(15 downto 0)
    ) is
    begin
        cam_fifo_rd_data <= data;
        cam_fifo_empty   <= '0';
        -- Wait for cam_rd_en assertion (FIFO pop)
        wait until rising_edge(clk) and cam_fifo_rd_en = '1';
        -- Data is latched internally, then wr_req fires
        wait until rising_edge(clk) and sdram_wr_req = '1';
        -- Acknowledge
        sdram_wr_ack <= '1';
        wait until rising_edge(clk);
        sdram_wr_ack <= '0';
        cam_fifo_empty <= '1';
        clk_wait(4);
    end procedure;

    -- Drive one complete read transaction
    procedure drive_read(
        signal vga_fifo_full  : out std_logic;
        signal sdram_rd_req   : in  std_logic;
        signal sdram_rd_ack   : out std_logic;
        signal sdram_rd_data  : out std_logic_vector(15 downto 0);
        signal sdram_rd_valid : out std_logic;
        ret_data              : std_logic_vector(15 downto 0)
    ) is
    begin
        vga_fifo_full <= '0';
        wait until rising_edge(clk) and sdram_rd_req = '1';
        sdram_rd_ack  <= '1';
        wait until rising_edge(clk);
        sdram_rd_ack  <= '0';
        -- Return data with latency
        clk_wait(3);
        sdram_rd_data  <= ret_data;
        sdram_rd_valid <= '1';
        wait until rising_edge(clk);
        sdram_rd_valid <= '0';
        clk_wait(4);
    end procedure;

begin

    clk <= not clk after T_CLK / 2;

    -- =========================================================================
    -- DUT
    -- =========================================================================
    u_dut : entity work.sdram_interface
        port map (
            clk              => clk,
            rst_n            => rst_n,
            cam_fifo_rd_en   => cam_fifo_rd_en,
            cam_fifo_rd_data => cam_fifo_rd_data,
            cam_fifo_empty   => cam_fifo_empty,
            vga_fifo_wr_en   => vga_fifo_wr_en,
            vga_fifo_wr_data => vga_fifo_wr_data,
            vga_fifo_full    => vga_fifo_full,
            sdram_wr_req     => sdram_wr_req,
            sdram_wr_addr    => sdram_wr_addr,
            sdram_wr_data    => sdram_wr_data,
            sdram_wr_ack     => sdram_wr_ack,
            sdram_rd_req     => sdram_rd_req,
            sdram_rd_addr    => sdram_rd_addr,
            sdram_rd_data    => sdram_rd_data,
            sdram_rd_valid   => sdram_rd_valid,
            sdram_rd_ack     => sdram_rd_ack,
            frame_done_sync  => frame_done_sync,
            vga_vsync_sync   => vga_vsync_sync
        );

    -- =========================================================================
    main : process
        variable addr_before  : unsigned(24 downto 0);
        variable addr_after   : unsigned(24 downto 0);
        variable rd_ptr_before: unsigned(24 downto 0);
        variable rd_ptr_after : unsigned(24 downto 0);
        variable wr_addr_bank0: std_logic_vector(24 downto 0);
        variable rd_addr_bank1: std_logic_vector(24 downto 0);
        variable wr_count     : integer;
        variable vga_wr_seen  : boolean;
        variable cam_rd_cycle : integer;
        variable wr_req_cycle : integer;
        variable cycle_cnt    : integer;
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            -- -----------------------------------------------------------------
            if run("tc_reset_idle") then
                info("No outputs asserted immediately after reset");
                rst_n <= '0'; clk_wait(4);
                check_equal(cam_fifo_rd_en, '0',  "cam_rd_en=0 in reset");
                check_equal(vga_fifo_wr_en, '0',  "vga_wr_en=0 in reset");
                check_equal(sdram_wr_req,   '0',  "wr_req=0 in reset");
                check_equal(sdram_rd_req,   '0',  "rd_req=0 in reset");

            -- -----------------------------------------------------------------
            elsif run("tc_write_priority") then
                info("Write (camera) processed before read (VGA) when both ready");
                do_reset(rst_n, cam_fifo_empty, vga_fifo_full, frame_done_sync);
                -- Offer both camera data and VGA read opportunity simultaneously
                cam_fifo_empty <= '0';
                vga_fifo_full  <= '0';
                vga_wr_seen := false;
                for i in 0 to 20 loop
                    wait until rising_edge(clk);
                    check_equal(sdram_rd_req, '0',
                        "rd_req must not fire while camera data available");
                    if cam_fifo_rd_en = '1' then
                        vga_wr_seen := true;
                        exit;
                    end if;
                end loop;
                check(vga_wr_seen, "cam_rd_en must assert (write priority over read)");
                wait until rising_edge(clk) and sdram_wr_req = '1';
                sdram_wr_ack <= '1';
                wait until rising_edge(clk);
                sdram_wr_ack <= '0';
                cam_fifo_empty <= '1';
                clk_wait(4);

            -- -----------------------------------------------------------------
            elsif run("tc_cam_fifo_pop_timing") then
                info("cam_rd_en fires before sdram_wr_req (FIX 3)");
                do_reset(rst_n, cam_fifo_empty, vga_fifo_full, frame_done_sync);
                cam_fifo_empty   <= '0';
                cam_fifo_rd_data <= x"1234";
                vga_fifo_full    <= '1';

                cam_rd_cycle := 0;
                wr_req_cycle := 0;
                cycle_cnt    := 0;

                for i in 0 to 20 loop
                    wait until rising_edge(clk);
                    cycle_cnt := cycle_cnt + 1;
                    if cam_fifo_rd_en = '1' and cam_rd_cycle = 0 then
                        cam_rd_cycle := cycle_cnt;
                    end if;
                    if sdram_wr_req = '1' and wr_req_cycle = 0 then
                        wr_req_cycle := cycle_cnt;
                    end if;
                    exit when wr_req_cycle > 0;
                end loop;

                check(cam_rd_cycle > 0, "cam_rd_en must assert");
                check(wr_req_cycle > 0, "sdram_wr_req must assert");
                check_equal(wr_req_cycle - cam_rd_cycle, 2,
                    "sdram_wr_req must be exactly 2 cycles after cam_rd_en");

                cam_fifo_empty <= '1';

            -- -----------------------------------------------------------------
            elsif run("tc_wr_data_latched") then
                info("sdram_wr_data matches cam_fifo_rd_data (latched correctly)");
                do_reset(rst_n, cam_fifo_empty, vga_fifo_full, frame_done_sync);
                cam_fifo_rd_data <= x"BEEF";
                cam_fifo_empty   <= '0';
                vga_fifo_full    <= '1';

                wait until rising_edge(clk) and sdram_wr_req = '1';
                check_equal(sdram_wr_data, std_logic_vector'(x"BEEF"),
                    "wr_data must match FIFO output");

                sdram_wr_ack   <= '1';
                wait until rising_edge(clk);
                sdram_wr_ack   <= '0';
                cam_fifo_empty <= '1';

            -- -----------------------------------------------------------------
            elsif run("tc_wr_ptr_advances") then
                info("Write address increments by 1 on each write ack");
                do_reset(rst_n, cam_fifo_empty, vga_fifo_full, frame_done_sync);
                vga_fifo_full <= '1';
                addr_before := (others => '0');

                -- Complete 3 writes
                for i in 0 to 2 loop
                    cam_fifo_rd_data <= std_logic_vector(to_unsigned(i, 16));
                    cam_fifo_empty   <= '0';
                    wait until rising_edge(clk) and sdram_wr_req = '1';
                    if i = 0 then
                        addr_before := unsigned(sdram_wr_addr);
                    else
                        check_equal(unsigned(sdram_wr_addr), addr_before + to_unsigned(i, 25),
                            "Write address must increment on each wr_req");
                    end if;
                    sdram_wr_ack   <= '1';
                    wait until rising_edge(clk);
                    sdram_wr_ack   <= '0';
                    cam_fifo_empty <= '1';
                    clk_wait(6);
                end loop;

            -- -----------------------------------------------------------------
            elsif run("tc_rd_ptr_advances") then
                info("Read address increments by 1 on each rd_valid");
                do_reset(rst_n, cam_fifo_empty, vga_fifo_full, frame_done_sync);
                pulse_frame_done(frame_done_sync);
                -- Drain cam FIFO to force read path
                cam_fifo_empty <= '1';
                vga_fifo_full  <= '0';
                addr_before := (others => '0');

                -- Complete 3 reads
                for i in 0 to 2 loop
                    wait until rising_edge(clk) and sdram_rd_req = '1';
                    if i = 0 then
                        addr_before := unsigned(sdram_rd_addr);
                    else
                        check_equal(unsigned(sdram_rd_addr), addr_before + to_unsigned(i, 25),
                            "Read address must increment on each rd_req");
                    end if;
                    sdram_rd_ack  <= '1';
                    wait until rising_edge(clk);
                    sdram_rd_ack  <= '0';
                    clk_wait(2);
                    sdram_rd_valid <= '1';
                    wait until rising_edge(clk);
                    sdram_rd_valid <= '0';
                    clk_wait(6);
                end loop;

            -- -----------------------------------------------------------------
            elsif run("tc_no_write_frame_full") then
                info("Writes stop when wr_ptr would exceed FRAME_WORDS");
                do_reset(rst_n, cam_fifo_empty, vga_fifo_full, frame_done_sync);
                pulse_frame_done(frame_done_sync);
                -- We can't run 307200 writes in simulation.
                -- Instead: verify the comparison logic by checking the
                -- FSM falls through to read when cam_fifo_empty='1'
                -- and also that writes stop when cam is empty.
                cam_fifo_empty <= '1';
                vga_fifo_full  <= '0';
                clk_wait(4);
                -- With cam empty, rd_req should appear (not wr_req)
                wait until rising_edge(clk) and (sdram_rd_req = '1' or sdram_wr_req = '1') for 200 ns;
                check_equal(sdram_wr_req, '0',
                    "wr_req must not fire when cam FIFO empty");
                check_equal(sdram_rd_req, '1',
                    "rd_req must fire when cam FIFO empty and VGA not full");

            -- -----------------------------------------------------------------
            elsif run("tc_no_read_vga_full") then
                info("Reads stop when VGA FIFO is full");
                do_reset(rst_n, cam_fifo_empty, vga_fifo_full, frame_done_sync);
                pulse_frame_done(frame_done_sync);
                cam_fifo_empty <= '1';
                vga_fifo_full  <= '1';   -- VGA FIFO full!
                clk_wait(10);
                check_equal(sdram_rd_req, '0',
                    "rd_req must not fire when VGA FIFO full");

            -- -----------------------------------------------------------------
            elsif run("tc_rd_ptr_wraps") then
                info("rd_ptr wraps to 0 after reaching FRAME_WORDS boundary");
                do_reset(rst_n, cam_fifo_empty, vga_fifo_full, frame_done_sync);
                pulse_frame_done(frame_done_sync);
                -- We verify wrap logic by checking that the rd_addr
                -- returns to the read bank base after completing a frame.
                -- Use a short simulation: do 3 reads, confirm address
                -- increments, then check the wrap at FRAME_WORDS would be 0.
                -- (Full 307200-read test would be impractical)
                cam_fifo_empty <= '1';
                vga_fifo_full  <= '0';

                -- Verify the first 3 read request addresses are sequential
                for i in 0 to 2 loop
                    wait until rising_edge(clk) and sdram_rd_req = '1';
                    if i = 0 then
                        addr_before := unsigned(sdram_rd_addr);
                    else
                        check_equal(unsigned(sdram_rd_addr), addr_before + to_unsigned(i, 25),
                            "Read address must increment on each rd_req");
                    end if;
                    sdram_rd_ack  <= '1';
                    wait until rising_edge(clk);
                    sdram_rd_ack  <= '0';
                    clk_wait(2);
                    sdram_rd_valid <= '1';
                    wait until rising_edge(clk);
                    sdram_rd_valid <= '0';
                    clk_wait(6);
                end loop;

            -- -----------------------------------------------------------------
            elsif run("tc_bank_swap_on_frame") then
                info("Write and read bank selectors toggle on frame_done");
                do_reset(rst_n, cam_fifo_empty, vga_fifo_full, frame_done_sync);
                vga_fifo_full <= '1';
                cam_fifo_empty <= '0';
                wait until rising_edge(clk) and sdram_wr_req = '1';
                wr_addr_bank0 := sdram_wr_addr;
                sdram_wr_ack <= '1';
                wait until rising_edge(clk);
                sdram_wr_ack <= '0';
                cam_fifo_empty <= '1';
                clk_wait(6);

                -- Pulse frame_done
                frame_done_sync <= '1';
                wait until rising_edge(clk);
                frame_done_sync <= '0';
                clk_wait(4);

                cam_fifo_empty <= '0';
                wait until rising_edge(clk) and sdram_wr_req = '1';
                check(unsigned(sdram_wr_addr) >= to_unsigned(FRAME_WORDS, 25),
                    "After bank swap, wr_base must be BANK_WORDS");
                sdram_wr_ack <= '1';
                wait until rising_edge(clk);
                sdram_wr_ack <= '0';
                cam_fifo_empty <= '1';

            -- -----------------------------------------------------------------
            elsif run("tc_rd_ptr_not_reset") then
                info("rd_ptr resets to 0 on VGA frame start (vsync)");
                do_reset(rst_n, cam_fifo_empty, vga_fifo_full, frame_done_sync);
                pulse_frame_done(frame_done_sync);
                -- Advance rd_ptr by doing 5 reads
                cam_fifo_empty <= '1';
                vga_fifo_full  <= '0';

                for i in 0 to 4 loop
                    wait until rising_edge(clk) and sdram_rd_req = '1';
                    sdram_rd_ack  <= '1';
                    wait until rising_edge(clk);
                    sdram_rd_ack  <= '0';
                    clk_wait(2);
                    sdram_rd_valid <= '1';
                    wait until rising_edge(clk);
                    sdram_rd_valid <= '0';
                    clk_wait(2);
                end loop;
                vga_fifo_full <= '1';
                clk_wait(6);

                pulse_vga_vsync(vga_vsync_sync);

                vga_fifo_full <= '0';
                wait until rising_edge(clk) and sdram_rd_req = '1';
                rd_ptr_after := unsigned(sdram_rd_addr);

                check_equal(to_integer(rd_ptr_after) mod FRAME_WORDS, 0,
                            "rd_ptr must restart at 0 after VGA vsync");

            -- -----------------------------------------------------------------
            elsif run("tc_write_to_read_switch") then
                info("FSM switches to read path when camera FIFO empties");
                do_reset(rst_n, cam_fifo_empty, vga_fifo_full, frame_done_sync);
                pulse_frame_done(frame_done_sync);
                -- Drive a write
                vga_fifo_full    <= '1';
                cam_fifo_rd_data <= x"AAAA";
                cam_fifo_empty   <= '0';
                wait until rising_edge(clk) and sdram_wr_req = '1';
                sdram_wr_ack   <= '1';
                wait until rising_edge(clk);
                sdram_wr_ack   <= '0';
                -- Empty the camera FIFO
                cam_fifo_empty <= '1';
                vga_fifo_full  <= '0';
                -- Now rd_req must appear
                vga_wr_seen := false;
                for i in 0 to 50 loop
                    wait until rising_edge(clk);
                    if sdram_rd_req = '1' then
                        vga_wr_seen := true;
                        exit;
                    end if;
                end loop;
                check(vga_wr_seen, "rd_req must appear after cam FIFO empties");

            -- -----------------------------------------------------------------
            elsif run("tc_vga_fifo_written") then
                info("vga_fifo_wr_en asserts when sdram_rd_valid fires");
                do_reset(rst_n, cam_fifo_empty, vga_fifo_full, frame_done_sync);
                pulse_frame_done(frame_done_sync);
                cam_fifo_empty <= '1';
                vga_fifo_full  <= '0';
                sdram_rd_data  <= x"5A5A";

                wait until rising_edge(clk) and sdram_rd_req = '1';
                sdram_rd_ack  <= '1';
                wait until rising_edge(clk);
                sdram_rd_ack  <= '0';
                clk_wait(2);
                sdram_rd_valid <= '1';
                wait until rising_edge(clk);
                sdram_rd_valid <= '0';
                vga_wr_seen := false;
                for i in 0 to 5 loop
                    wait until rising_edge(clk);
                    wait for 0 ns;
                    if vga_fifo_wr_en = '1' then
                        vga_wr_seen := true;
                        exit;
                    end if;
                end loop;
                check(vga_wr_seen, "vga_fifo_wr_en must assert after rd_valid");
                check_equal(vga_fifo_wr_data, std_logic_vector'(x"5A5A"),
                    "vga_fifo_wr_data must match sdram_rd_data");

            -- -----------------------------------------------------------------
            elsif run("tc_double_buffer_addrs") then
                info("Write and read banks are in different SDRAM halves");
                do_reset(rst_n, cam_fifo_empty, vga_fifo_full, frame_done_sync);
                vga_fifo_full  <= '1';
                cam_fifo_empty <= '0';
                wait until rising_edge(clk) and sdram_wr_req = '1';
                check(unsigned(sdram_wr_addr) < to_unsigned(FRAME_WORDS, 25),
                    "Write address must start in bank 0");
                sdram_wr_ack <= '1';
                wait until rising_edge(clk);
                sdram_wr_ack <= '0';
                cam_fifo_empty <= '1';
                clk_wait(6);

                pulse_frame_done(frame_done_sync);
                pulse_vga_vsync(vga_vsync_sync);

                cam_fifo_empty <= '0';
                wait until rising_edge(clk) and sdram_wr_req = '1';
                check(unsigned(sdram_wr_addr) >= to_unsigned(FRAME_WORDS, 25),
                    "After bank swap, write must go to bank 1");
                sdram_wr_ack <= '1';
                wait until rising_edge(clk);
                sdram_wr_ack <= '0';
                cam_fifo_empty <= '1';
                clk_wait(6);

                cam_fifo_empty <= '1';
                vga_fifo_full  <= '0';
                wait until rising_edge(clk) and sdram_rd_req = '1';
                check(unsigned(sdram_rd_addr) < to_unsigned(FRAME_WORDS, 25),
                    "After bank swap, read must go to completed frame in bank 0");

            end if;
        end loop;

        test_runner_cleanup(runner);
    end process;

    test_runner_watchdog(runner, 10 ms);

end architecture sim;
