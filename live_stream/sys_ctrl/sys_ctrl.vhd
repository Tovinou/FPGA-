-- =============================================================================
-- sys_ctrl.vhd
-- System controller: global reset generation
--
-- Responsibilities:
--   1. Debounce KEY[0] (active-low reset button)
--   2. Gate reset release on pll_locked
--   3. Synchronise reset into 50 MHz domain (2-FF)
--   4. Output a single active-low rst_n used by all subsystems
--
-- Reset is asserted  when: KEY[0] pressed  OR  PLL not locked
-- Reset is deasserted when: KEY[0] released AND PLL locked (held for 2 cycles)
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sys_ctrl is
    port (
        clk_50m    : in  std_logic;
        pll_locked : in  std_logic;
        key0       : in  std_logic;   -- raw KEY[0], active low
        rst_n      : out std_logic;   -- synchronised active-low reset
        -- debug
        locked_led : out std_logic
    );
end entity sys_ctrl;

architecture rtl of sys_ctrl is

    -- debounce_explicit component
    component debounce_explicit
        generic (
            CLK_FREQ_HZ : integer;
            DEBOUNCE_MS : integer
        );
        port (
            clk       : in  std_logic;
            rst_n     : in  std_logic;
            btn_in    : in  std_logic;
            btn_out   : out std_logic;
            btn_level : out std_logic
        );
    end component;

    signal btn_level   : std_logic;
    signal rst_comb    : std_logic;
    signal rst_sync1   : std_logic := '0';
    signal rst_sync2   : std_logic := '0';

begin

    locked_led <= pll_locked;

    -- -------------------------------------------------------------------------
    -- Debounce KEY[0]
    -- btn_level is active-high when button is NOT pressed (KEY=1 = released)
    -- -------------------------------------------------------------------------
    u_db : debounce_explicit
        generic map (
            CLK_FREQ_HZ => 50_000_000,
            DEBOUNCE_MS => 20
        )
        port map (
            clk       => clk_50m,
            rst_n     => '1',
            btn_in    => key0,
            btn_out   => open,
            btn_level => btn_level
        );

    -- -------------------------------------------------------------------------
    -- Reset is released only when PLL locked AND button not pressed
    -- btn_level='1' means button released (KEY[0] high = not pressed)
    -- -------------------------------------------------------------------------
    rst_comb <= pll_locked and btn_level;

    -- -------------------------------------------------------------------------
    -- 2-FF synchroniser into 50 MHz domain
    -- -------------------------------------------------------------------------
    p_sync : process(clk_50m)
    begin
        if rising_edge(clk_50m) then
            rst_sync1 <= rst_comb;
            rst_sync2 <= rst_sync1;
        end if;
    end process;

    rst_n <= rst_sync2;

end architecture rtl;
