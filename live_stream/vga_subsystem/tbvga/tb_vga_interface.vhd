-- =============================================================================
-- tb_vga_interface.vhd
-- VUnit testbench for vga_interface.vhd only
--
-- The FIFO and vga_core are replaced by direct TB stimulus signals.
--
-- Tests:
--   tc_reset           : outputs in safe idle after reset
--   tc_rgb565_red      : pure red pixel maps correctly to DAC
--   tc_rgb565_green    : pure green pixel maps correctly to DAC
--   tc_rgb565_blue     : pure blue pixel maps correctly to DAC
--   tc_rgb565_white    : white pixel (all max)
--   tc_rgb565_black    : black pixel (all zero)
--   tc_rgb565_midgrey  : mid grey value through all channels
--   tc_blanking        : DAC outputs 0000 when active=0
--   tc_underrun        : DAC black and rd_en=0 when FIFO empty
--   tc_rd_en_logic     : rd_en only when active=1 AND fifo_empty=0
--   tc_sync_pipeline   : hsync/vsync delayed exactly 1 clock cycle
--   tc_active_d        : DAC gated by registered active_d not raw active
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_vga_interface is
    generic (runner_cfg : string);
end entity;

architecture sim of tb_vga_interface is

    constant T_CLK : time := 40 ns;  -- 25 MHz

    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';

    -- FIFO stimulus
    signal fifo_rd_en   : std_logic;
    signal fifo_rd_data : std_logic_vector(15 downto 0) := (others => '0');
    signal fifo_empty   : std_logic := '1';

    -- Timing stimulus (normally from vga_core)
    signal active       : std_logic := '0';
    signal hsync_in     : std_logic := '1';
    signal vsync_in     : std_logic := '1';
    signal h_count      : std_logic_vector(9 downto 0) := (others => '0');
    signal v_count      : std_logic_vector(9 downto 0) := (others => '0');

    -- DAC outputs
    signal vga_r        : std_logic_vector(3 downto 0);
    signal vga_g        : std_logic_vector(3 downto 0);
    signal vga_b        : std_logic_vector(3 downto 0);
    signal vga_hs       : std_logic;
    signal vga_vs       : std_logic;

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

    -- Build RGB565 word from 5-bit R, 6-bit G, 5-bit B
    function rgb565(r5, g6, b5 : natural) return std_logic_vector is
    begin
        return std_logic_vector(
            to_unsigned(r5, 5) & to_unsigned(g6, 6) & to_unsigned(b5, 5)
        );
    end function;

    -- Drive one pixel and check DAC output
    -- Pipeline latency:
    --   1) rd_en asserted, FIFO output becomes visible to DUT next cycle
    --   2) src_pixel updates (registered)
    --   3) pixel updates from src_pixel (registered)
    --   4) DAC gated by active_d (registered)
    -- For stable checks, wait 3 clocks after driving stimulus.
    procedure drive_pixel(
        signal fifo_rd_data_out : out std_logic_vector(15 downto 0);
        signal fifo_empty_out   : out std_logic;
        signal active_out       : out std_logic;
        r5, g6, b5  : natural;
        exp_r, exp_g, exp_b : std_logic_vector(3 downto 0);
        tag         : string
    ) is
    begin
        fifo_rd_data_out <= rgb565(r5, g6, b5);
        fifo_empty_out   <= '0';
        active_out       <= '1';
        clk_wait(3);
        wait for 0 ns;
        wait for 0 ns;
        check_equal(vga_r, exp_r, tag & " R channel");
        check_equal(vga_g, exp_g, tag & " G channel");
        check_equal(vga_b, exp_b, tag & " B channel");
    end procedure;

begin

    clk <= not clk after T_CLK / 2;

    u_dut : entity work.vga_interface
        port map (
            pclk         => clk,
            rst_n        => rst_n,
            test_mode    => "00",
            rd_gate      => '1',
            fifo_rd_en   => fifo_rd_en,
            fifo_rd_data => fifo_rd_data,
            fifo_empty   => fifo_empty,
            active       => active,
            h_count      => h_count,
            v_count      => v_count,
            hsync_in     => hsync_in,
            vsync_in     => vsync_in,
            vga_r        => vga_r,
            vga_g        => vga_g,
            vga_b        => vga_b,
            vga_hs       => vga_hs,
            vga_vs       => vga_vs
        );

    main : process
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            -- -----------------------------------------------------------------
            if run("tc_reset") then
                info("Reset: safe idle outputs");
                rst_n <= '0';
                clk_wait(6);
                check_equal(vga_r,  std_logic_vector'("0000"), "R=0 in reset");
                check_equal(vga_g,  std_logic_vector'("0000"), "G=0 in reset");
                check_equal(vga_b,  std_logic_vector'("0000"), "B=0 in reset");
                check_equal(vga_hs, std_logic'('1'),    "HS idle high in reset");
                check_equal(vga_vs, std_logic'('1'),    "VS idle high in reset");

            -- -----------------------------------------------------------------
            elsif run("tc_rgb565_red") then
                info("Pure red: R5=11111 G6=000000 B5=00000");
                do_reset(rst_n);
                -- RGB565: 1111_1000_0000_0000
                -- DAC:    R=1111  G=0000  B=0000
                drive_pixel(fifo_rd_data, fifo_empty, active,
                            31, 0, 0, "1111", "0000", "0000", "pure red");

            -- -----------------------------------------------------------------
            elsif run("tc_rgb565_green") then
                info("Pure green: R5=00000 G6=111111 B5=00000");
                do_reset(rst_n);
                -- RGB565: 0000_0111_1110_0000
                -- DAC:    R=0000  G=1111  B=0000
                drive_pixel(fifo_rd_data, fifo_empty, active,
                            0, 63, 0, "0000", "1111", "0000", "pure green");

            -- -----------------------------------------------------------------
            elsif run("tc_rgb565_blue") then
                info("Pure blue: R5=00000 G6=000000 B5=11111");
                do_reset(rst_n);
                -- RGB565: 0000_0000_0001_1111
                -- DAC:    R=0000  G=0000  B=1111
                drive_pixel(fifo_rd_data, fifo_empty, active,
                            0, 0, 31, "0000", "0000", "1111", "pure blue");

            -- -----------------------------------------------------------------
            elsif run("tc_rgb565_white") then
                info("White: all channels max");
                do_reset(rst_n);
                drive_pixel(fifo_rd_data, fifo_empty, active,
                            31, 63, 31, "1111", "1111", "1111", "white");

            -- -----------------------------------------------------------------
            elsif run("tc_rgb565_black") then
                info("Black: all channels zero");
                do_reset(rst_n);
                drive_pixel(fifo_rd_data, fifo_empty, active,
                            0, 0, 0, "0000", "0000", "0000", "black");

            -- -----------------------------------------------------------------
            elsif run("tc_rgb565_midgrey") then
                info("Mid grey: R5=01111 G6=011111 B5=01111");
                do_reset(rst_n);
                -- R[15:11]=01111 -> top 4 = 0111
                -- G[10:5] =011111 -> top 4 = 0111 (bits 10..7)
                -- B[4:0]  =01111 -> top 4 = 0111 (bits 4..1)
                drive_pixel(fifo_rd_data, fifo_empty, active,
                            15, 31, 15, "0111", "0111", "0111", "mid grey");

            -- -----------------------------------------------------------------
            elsif run("tc_blanking") then
                info("Blanking: DAC=0000 regardless of pixel data");
                do_reset(rst_n);
                fifo_rd_data <= rgb565(31, 63, 31);  -- white data
                fifo_empty   <= '0';
                active       <= '0';   -- blanking!
                clk_wait(3);
                check_equal(vga_r, std_logic_vector'("0000"), "R=0 in blanking");
                check_equal(vga_g, std_logic_vector'("0000"), "G=0 in blanking");
                check_equal(vga_b, std_logic_vector'("0000"), "B=0 in blanking");

            -- -----------------------------------------------------------------
            elsif run("tc_underrun") then
                info("FIFO underrun: black output, rd_en=0");
                do_reset(rst_n);
                fifo_empty   <= '1';   -- empty!
                active       <= '1';
                fifo_rd_data <= rgb565(31, 63, 31);  -- data doesn't matter
                clk_wait(3);
                check_equal(vga_r,      std_logic_vector'("0000"), "R=0 on underrun");
                check_equal(vga_g,      std_logic_vector'("0000"), "G=0 on underrun");
                check_equal(vga_b,      std_logic_vector'("0000"), "B=0 on underrun");
                check_equal(fifo_rd_en, std_logic'('0'),    "rd_en=0 when FIFO empty");

            -- -----------------------------------------------------------------
            elsif run("tc_rd_en_logic") then
                info("rd_en = active AND NOT fifo_empty AND h_count(0)=0 AND v_count(0)=0");
                do_reset(rst_n);

                -- Case 1: active=0, empty=0 -> rd_en must be 0
                active     <= '0';
                fifo_empty <= '0';
                h_count    <= (others => '0');
                v_count    <= (others => '0');
                clk_wait(2);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(fifo_rd_en, std_logic'('0'), "rd_en=0 when active=0");

                -- Case 2: active=1, empty=0 -> rd_en must be 1
                active <= '1';
                -- rd_en is deliberately gated by active_d, so allow the
                -- active flag to register before checking the request.
                clk_wait(2);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(fifo_rd_en, std_logic'('1'), "rd_en=1 when active=1, not empty");

                -- Case 3: active=1, empty=1 -> rd_en must be 0
                fifo_empty <= '1';
                wait until rising_edge(clk);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(fifo_rd_en, std_logic'('0'), "rd_en=0 when FIFO empty");

                -- Case 4: active=1, empty=0 but odd h_count -> rd_en must be 0
                fifo_empty <= '0';
                h_count(0) <= '1';
                wait until rising_edge(clk);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(fifo_rd_en, std_logic'('0'), "rd_en=0 when h_count is odd");

                -- Case 5: active=1, empty=0 but odd v_count -> rd_en must be 0
                h_count(0) <= '0';
                v_count(0) <= '1';
                wait until rising_edge(clk);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(fifo_rd_en, std_logic'('0'), "rd_en=0 when v_count is odd");

                -- Case 6: back to active=0, empty=0 -> rd_en must be 0
                active     <= '0';
                v_count(0) <= '0';
                -- active_d also delays the deassertion by one clock.
                clk_wait(2);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(fifo_rd_en, std_logic'('0'), "rd_en=0 when active=0 again");

            -- -----------------------------------------------------------------
            elsif run("tc_sync_pipeline") then
                info("hsync/vsync registered: output lags input by 1 clock");
                do_reset(rst_n);
                hsync_in <= '1';
                vsync_in <= '1';
                clk_wait(2);

                -- Drive hsync low — output must still be high this cycle
                hsync_in <= '0';
                check_equal(vga_hs, std_logic'('1'), "hs not yet low before clock edge");
                wait until rising_edge(clk);
                wait for 0 ns;
                check_equal(vga_hs, std_logic'('0'), "hs low 1 cycle after input fell");

                -- Restore hsync, check it comes back high
                hsync_in <= '1';
                wait until rising_edge(clk);
                wait for 0 ns;
                check_equal(vga_hs, std_logic'('1'), "hs high 1 cycle after input rose");

                -- Same test for vsync
                vsync_in <= '0';
                check_equal(vga_vs, std_logic'('1'), "vs not yet low before clock edge");
                wait until rising_edge(clk);
                wait for 0 ns;
                check_equal(vga_vs, std_logic'('0'), "vs low 1 cycle after input fell");
                vsync_in <= '1';
                wait until rising_edge(clk);
                wait for 0 ns;
                check_equal(vga_vs, std_logic'('1'), "vs high 1 cycle after input rose");

            -- -----------------------------------------------------------------
            elsif run("tc_active_d") then
                info("DAC gated by active_d (registered), not raw active");
                do_reset(rst_n);
                fifo_rd_data <= rgb565(31, 63, 31);  -- white
                fifo_empty   <= '0';

                -- Bring active high
                active <= '1';
                -- First clock: rd_en_q still 0, pixel still 0, active_d rises
                wait until rising_edge(clk);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(vga_r, std_logic_vector'("0000"),
                    "DAC still 0 on first cycle after active rises");
                -- Second clock: src_pixel captures fifo data, pixel still previous
                wait until rising_edge(clk);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(vga_r, std_logic_vector'("0000"),
                    "DAC still 0 while pixel pipeline fills");
                -- Third clock: pixel shows data, active_d=1
                wait until rising_edge(clk);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(vga_r, std_logic_vector'("1111"),
                    "DAC shows pixel once pipeline is filled");

                -- Drop active, DAC must go black next cycle
                active <= '0';
                wait until rising_edge(clk);
                wait for 0 ns;
                wait for 0 ns;
                check_equal(vga_r, std_logic_vector'("0000"),
                    "DAC=0 1 cycle after active falls");

            end if;
        end loop;

        test_runner_cleanup(runner);
    end process;

    test_runner_watchdog(runner, 5 ms);

end architecture sim;
