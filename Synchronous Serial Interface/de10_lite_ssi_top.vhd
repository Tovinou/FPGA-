-- =============================================================================
-- de10_lite_ssi_top.vhd
-- DE10-Lite SSI Encoder Reader — Structural Top-Level
--
-- This file contains NO logic.  It only declares and connects sub-modules.
--
-- Full design hierarchy:
--
--   de10_lite_ssi_top                   <- this file
--   |-- u_key1_det  : falling_edge_det  <- synchronise + detect KEY(1) press
--   |-- u_trig      : trigger_gen       <- combine manual & auto-retrigger
--   |-- u_ssi       : ssi_master        <- SSI protocol engine
--   |   |-- u_clk_div : ssi_clk_div
--   |   |-- u_fsm     : ssi_fsm
--   |   |-- u_shift   : ssi_shift
--   |   `-- u_clk_out : ssi_clk_out
--   |-- u_pos_latch : pos_latch         <- capture position on valid pulse
--   `-- u_display   : display_ctrl      <- drive HEX0-5 and LEDs
--       `-- u_hex0..u_hex5 : seg7_decoder
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.ssi_pkg.all;

entity de10_lite_ssi_top is
    port (
        MAX10_CLK1_50 : in  std_logic;
        KEY           : in  std_logic_vector(1 downto 0);
        SW            : in  std_logic_vector(9 downto 0);

        GPIO_0_0 : out std_logic;
        GPIO_0_1 : in  std_logic;

        HEX0 : out std_logic_vector(7 downto 0);
        HEX1 : out std_logic_vector(7 downto 0);
        HEX2 : out std_logic_vector(7 downto 0);
        HEX3 : out std_logic_vector(7 downto 0);
        HEX4 : out std_logic_vector(7 downto 0);
        HEX5 : out std_logic_vector(7 downto 0);

        LEDR : out std_logic_vector(9 downto 0)
    );
end entity de10_lite_ssi_top;

architecture structural of de10_lite_ssi_top is

    component falling_edge_det is
        generic (STAGES : positive);
        port (
            clk   : in  std_logic;
            rst_n : in  std_logic;
            pin   : in  std_logic;
            pulse : out std_logic
        );
    end component;

    component trigger_gen is
        port (
            clk         : in  std_logic;
            rst_n       : in  std_logic;
            manual_trig : in  std_logic;
            busy        : in  std_logic;
            sw_auto     : in  std_logic;
            start_pulse : out std_logic
        );
    end component;

    component ssi_master is
        generic (
            CLK_FREQ_HZ : positive;
            SSI_CLK_HZ  : positive;
            DATA_BITS   : positive
        );
        port (
            clk      : in  std_logic;
            rst_n    : in  std_logic;
            start    : in  std_logic;
            busy     : out std_logic;
            valid    : out std_logic;
            position : out std_logic_vector(DATA_BITS - 1 downto 0);
            ssi_clk  : out std_logic;
            ssi_data : in  std_logic
        );
    end component;

    component pos_latch is
        generic (DATA_BITS : positive);
        port (
            clk     : in  std_logic;
            rst_n   : in  std_logic;
            valid   : in  std_logic;
            data_in : in  std_logic_vector(DATA_BITS - 1 downto 0);
            pos_out : out std_logic_vector(DATA_BITS - 1 downto 0)
        );
    end component;

    component display_ctrl is
        port (
            pos  : in  std_logic_vector(24 downto 0);
            HEX0 : out std_logic_vector(7 downto 0);
            HEX1 : out std_logic_vector(7 downto 0);
            HEX2 : out std_logic_vector(7 downto 0);
            HEX3 : out std_logic_vector(7 downto 0);
            HEX4 : out std_logic_vector(7 downto 0);
            HEX5 : out std_logic_vector(7 downto 0);
            LEDR : out std_logic_vector(9 downto 0)
        );
    end component;

    -- Internal signals
    signal clk         : std_logic;
    signal rst_n       : std_logic;
    signal manual_trig : std_logic;
    signal start_pulse : std_logic;
    signal busy        : std_logic;
    signal valid       : std_logic;
    signal position    : std_logic_vector(24 downto 0);
    signal ssi_clk_sig : std_logic;
    signal pos_latched : std_logic_vector(24 downto 0);

begin

    clk      <= MAX10_CLK1_50;
    rst_n    <= KEY(0);
    GPIO_0_0 <= ssi_clk_sig;

    -- =========================================================================
    -- u_key1_det : falling_edge_det
    -- Synchronises KEY(1) and detects the falling edge (button press).
    -- =========================================================================
    u_key1_det : falling_edge_det
        generic map (STAGES => 2)
        port map (
            clk   => clk,
            rst_n => rst_n,
            pin   => KEY(1),
            pulse => manual_trig
        );

    -- =========================================================================
    -- u_trig : trigger_gen
    -- Merges manual and auto-retrigger sources into a single start_pulse.
    -- =========================================================================
    u_trig : trigger_gen
        port map (
            clk         => clk,
            rst_n       => rst_n,
            manual_trig => manual_trig,
            busy        => busy,
            sw_auto     => SW(9),
            start_pulse => start_pulse
        );

    -- =========================================================================
    -- u_ssi : ssi_master
    -- SSI protocol engine (clk_div / fsm / shift / clk_out).
    -- =========================================================================
    u_ssi : ssi_master
        generic map (
            CLK_FREQ_HZ => 50_000_000,
            SSI_CLK_HZ  => 500_000,
            DATA_BITS   => 25
        )
        port map (
            clk      => clk,
            rst_n    => rst_n,
            start    => start_pulse,
            busy     => busy,
            valid    => valid,
            position => position,
            ssi_clk  => ssi_clk_sig,
            ssi_data => GPIO_0_1
        );

    -- =========================================================================
    -- u_pos_latch : pos_latch
    -- Holds the last captured encoder position stable between SSI frames.
    -- =========================================================================
    u_pos_latch : pos_latch
        generic map (DATA_BITS => 25)
        port map (
            clk     => clk,
            rst_n   => rst_n,
            valid   => valid,
            data_in => position,
            pos_out => pos_latched
        );

    -- =========================================================================
    -- u_display : display_ctrl
    -- Routes latched position bits to six 7-segment displays and ten LEDs.
    -- =========================================================================
    u_display : display_ctrl
        port map (
            pos  => pos_latched,
            HEX0 => HEX0,
            HEX1 => HEX1,
            HEX2 => HEX2,
            HEX3 => HEX3,
            HEX4 => HEX4,
            HEX5 => HEX5,
            LEDR => LEDR
        );

end architecture structural;
