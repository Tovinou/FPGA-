-- =============================================================================
-- falling_edge_det.vhd
-- Falling-Edge Detector for Active-Low Push-Buttons (DE10-Lite KEY pins)
--
-- The DE10-Lite KEY buttons are active-low: the pin is normally '1' and goes
-- to '0' when the button is pressed.  A button press is therefore a falling
-- edge on the pin.
--
-- This module uses a 2-stage synchroniser shift register to:
--   1. Synchronise the asynchronous button pin to the system clock domain.
--   2. Detect the falling edge (pin transition 1 → 0).
--
-- Output 'pulse' is asserted HIGH for exactly one system-clock cycle on each
-- detected falling edge (i.e. each button press).
--
-- Generic STAGES controls the synchroniser depth (default 2 — sufficient for
-- a slow human-operated button; increase to 3 for noisy inputs).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity falling_edge_det is
    generic (
        STAGES : positive := 2   -- Synchroniser depth (2 is standard)
    );
    port (
        clk   : in  std_logic;
        rst_n : in  std_logic;
        pin   : in  std_logic;   -- Active-low button pin (async)
        pulse : out std_logic    -- One-cycle HIGH pulse on button press
    );
end entity falling_edge_det;

architecture rtl of falling_edge_det is

    -- Shift register: index 0 is the freshest sample
    signal sr : std_logic_vector(STAGES - 1 downto 0);

begin

    p_sync : process (clk, rst_n)
    begin
        if rst_n = '0' then
            -- Reset to all-high (button released / idle state)
            sr <= (others => '1');
        elsif rising_edge(clk) then
            -- Shift in new sample at MSB; index 0 is oldest
            sr <= sr(STAGES - 2 downto 0) & pin;
        end if;
    end process p_sync;

    -- Falling edge: most-recent sample is '0', previous sample was '1'
    -- sr(STAGES-1) holds the oldest captured value
    -- sr(0)        holds the most-recently captured value
    --
    -- Pattern for falling edge: sr(STAGES-1)='1', sr(0)='0'
    pulse <= '1' when (sr(STAGES - 1) = '1' and sr(0) = '0') else '0';

end architecture rtl;
