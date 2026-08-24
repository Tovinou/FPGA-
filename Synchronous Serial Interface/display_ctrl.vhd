-- =============================================================================
-- display_ctrl.vhd
-- Display Controller
--
-- Maps the 25-bit encoder position word to the six 7-segment displays and
-- the ten LEDs on the DE10-Lite.
--
--   HEX0 ← pos(3:0)    (least-significant hex digit)
--   HEX1 ← pos(7:4)
--   HEX2 ← pos(11:8)
--   HEX3 ← pos(15:12)
--   HEX4 ← pos(19:16)
--   HEX5 ← pos(23:20)  (most-significant hex digit shown on display)
--   LEDR ← pos(24:15)  (upper 10 bits on LEDs as a bar-graph)
--
-- Each HEX output is driven by an instantiated seg7_decoder.
-- The module is purely structural/concurrent — no clock required.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity display_ctrl is
    port (
        pos  : in  std_logic_vector(24 downto 0);  -- Latched encoder position

        -- 7-segment outputs (active-low)
        HEX0 : out std_logic_vector(7 downto 0);
        HEX1 : out std_logic_vector(7 downto 0);
        HEX2 : out std_logic_vector(7 downto 0);
        HEX3 : out std_logic_vector(7 downto 0);
        HEX4 : out std_logic_vector(7 downto 0);
        HEX5 : out std_logic_vector(7 downto 0);

        -- LED outputs
        LEDR : out std_logic_vector(9 downto 0)
    );
end entity display_ctrl;

architecture structural of display_ctrl is

    component seg7_decoder is
        port (
            digit : in  std_logic_vector(3 downto 0);
            seg   : out std_logic_vector(7 downto 0)
        );
    end component;

begin

    -- Six hex digits driven by individual seg7_decoder instances
    u_hex0 : seg7_decoder port map (digit => pos( 3 downto  0), seg => HEX0);
    u_hex1 : seg7_decoder port map (digit => pos( 7 downto  4), seg => HEX1);
    u_hex2 : seg7_decoder port map (digit => pos(11 downto  8), seg => HEX2);
    u_hex3 : seg7_decoder port map (digit => pos(15 downto 12), seg => HEX3);
    u_hex4 : seg7_decoder port map (digit => pos(19 downto 16), seg => HEX4);
    u_hex5 : seg7_decoder port map (digit => pos(23 downto 20), seg => HEX5);

    -- Upper 10 bits to LEDs (simple wire assignment)
    LEDR <= pos(24 downto 15);

end architecture structural;
