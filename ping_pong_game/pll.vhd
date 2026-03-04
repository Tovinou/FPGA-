-- =============================================================================
-- PLL STUB / QUARTUS MEGAFUNCTION PLACEHOLDER
-- =============================================================================
-- In Quartus Prime, you MUST generate this PLL using the MegaWizard:
--   Tools -> IP Catalog -> Library -> Basic Functions -> Clocks; PLLs and Resets
--   -> ALTPLL
--
-- Settings:
--   Input clock:   inclk0 = 50 MHz
--   Output clock:  c0     = 25 MHz  (for VGA 640x480 @ 60 Hz)
--   Output clock:  c1     = 50 MHz  (optional, same as input, for convenience)
--
-- The generated file will be named "pll.vhd" (or pll.qip / pll.v depending on
-- Quartus version). Replace THIS file with the generated one.
--
-- This stub allows synthesis flow to proceed for review; it simply passes the
-- clock through divided by 2 for simulation purposes ONLY.
-- =============================================================================
library IEEE;
use IEEE.std_logic_1164.ALL;

entity pll is
    port (
        inclk0 : in  std_logic;   -- 50 MHz input
        c0     : out std_logic    -- 25 MHz output
    );
end pll;

architecture sim_stub of pll is
    signal clk_div : std_logic := '0';
begin
    -- Divide by 2: 50 MHz -> 25 MHz (simulation only)
    process(inclk0)
    begin
        if rising_edge(inclk0) then
            clk_div <= not clk_div;
        end if;
    end process;

    c0 <= clk_div;
end sim_stub;
