-- =============================================================================
-- ssi_master.vhd
-- SSI Master — structural top-level
--
-- Wires the four sub-modules together. Contains no logic of its own.
--
-- Hierarchy:
--   ssi_master
--   ├── u_clk_div : ssi_clk_div   — half-period enable tick
--   ├── u_fsm     : ssi_fsm       — FSM + monoflop counter
--   ├── u_shift   : ssi_shift     — serial shift register + bit counter
--   └── u_clk_out : ssi_clk_out   — physical ssi_clk pin driver
--
-- Generics
--   CLK_FREQ_HZ : system clock frequency (default 50 MHz for DE10-Lite)
--   SSI_CLK_HZ  : SSI clock rate (default 500 kHz; typical max ~2 MHz)
--   DATA_BITS   : encoder resolution in bits (default 25)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.ssi_pkg.all;

entity ssi_master is
    generic (
        CLK_FREQ_HZ : positive := 50_000_000;
        SSI_CLK_HZ  : positive := 500_000;
        DATA_BITS   : positive := 25
    );
    port (
        clk      : in  std_logic;
        rst_n    : in  std_logic;
        -- Control
        start    : in  std_logic;
        busy     : out std_logic;
        valid    : out std_logic;
        -- Data
        position : out std_logic_vector(DATA_BITS - 1 downto 0);
        -- SSI physical interface
        ssi_clk  : out std_logic;
        ssi_data : in  std_logic
    );
end entity ssi_master;

architecture structural of ssi_master is

    -- Internal signals
    signal w_state     : t_ssi_state;
    signal w_clk_en    : std_logic;
    signal w_active    : std_logic;
    signal w_clk_phase : std_logic;
    signal w_last_bit  : std_logic;
    signal w_latch     : std_logic;
    signal w_shifting  : std_logic;

begin

    -- latch fires during the single cycle that FSM is in DONE
    w_latch    <= '1' when w_state = DONE     else '0';
    w_shifting <= '1' when w_state = SHIFTING else '0';

    -- -------------------------------------------------------------------------
    -- Clock Divider
    -- -------------------------------------------------------------------------
    u_clk_div : entity work.ssi_clk_div
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            SSI_CLK_HZ  => SSI_CLK_HZ
        )
        port map (
            clk    => clk,
            rst_n  => rst_n,
            active => w_active,
            clk_en => w_clk_en
        );

    -- -------------------------------------------------------------------------
    -- FSM
    -- -------------------------------------------------------------------------
    u_fsm : entity work.ssi_fsm
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            DATA_BITS   => DATA_BITS
        )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            start     => start,
            clk_en    => w_clk_en,
            clk_phase => w_clk_phase,
            last_bit  => w_last_bit,
            state     => w_state,
            active    => w_active,
            busy      => busy,
            valid     => valid
        );

    -- -------------------------------------------------------------------------
    -- Shift Engine
    -- -------------------------------------------------------------------------
    u_shift : entity work.ssi_shift
        generic map (
            DATA_BITS => DATA_BITS
        )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            shifting  => w_shifting,
            latch     => w_latch,
            clk_en    => w_clk_en,
            ssi_data  => ssi_data,
            clk_phase => w_clk_phase,
            last_bit  => w_last_bit,
            data_out  => position
        );

    -- -------------------------------------------------------------------------
    -- SSI Clock Output Driver
    -- -------------------------------------------------------------------------
    u_clk_out : entity work.ssi_clk_out
        port map (
            clk     => clk,
            rst_n   => rst_n,
            state   => w_state,
            clk_en  => w_clk_en,
            ssi_clk => ssi_clk
        );

end architecture structural;
