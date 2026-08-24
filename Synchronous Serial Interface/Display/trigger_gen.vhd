-- =============================================================================
-- trigger_gen.vhd
-- SSI Start-Pulse Generator
--
-- Combines a manual trigger (from falling_edge_det) with an automatic
-- re-trigger mode controlled by a slide switch.
--
-- Manual mode  (SW_auto = '0'):
--   A single start pulse is generated each time the operator presses KEY(1).
--
-- Auto mode    (SW_auto = '1'):
--   The SSI master is re-triggered automatically after every completed frame.
--   The falling edge of 'busy' (transaction complete) causes a new start pulse,
--   giving continuous back-to-back reads as fast as the monoflop allows.
--
-- In both modes 'start_pulse' is asserted for exactly one system-clock cycle.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity trigger_gen is
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        manual_trig : in  std_logic;   -- One-cycle pulse from falling_edge_det
        busy        : in  std_logic;   -- From ssi_master
        sw_auto     : in  std_logic;   -- SW(9): '1' = continuous mode
        start_pulse : out std_logic    -- To ssi_master start input
    );
end entity trigger_gen;

architecture rtl of trigger_gen is

    signal busy_prev : std_logic;
    signal busy_fell : std_logic;   -- One-cycle pulse on falling edge of busy

begin

    -- -------------------------------------------------------------------------
    -- Detect falling edge of busy (frame complete)
    -- -------------------------------------------------------------------------
    p_busy_edge : process (clk, rst_n)
    begin
        if rst_n = '0' then
            busy_prev <= '0';
        elsif rising_edge(clk) then
            busy_prev <= busy;
        end if;
    end process p_busy_edge;

    -- busy_fell: one-cycle pulse when busy transitions 1 → 0
    busy_fell <= busy_prev and (not busy);

    -- -------------------------------------------------------------------------
    -- Combine manual and auto triggers
    -- -------------------------------------------------------------------------
    start_pulse <= manual_trig or (sw_auto and busy_fell);

end architecture rtl;
