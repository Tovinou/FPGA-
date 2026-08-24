-- =============================================================================
-- ssi_pkg.vhd
-- Shared package for the SSI Master design.
-- Defines the FSM state type used by every sub-module.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package ssi_pkg is

    type t_ssi_state is (
        IDLE,       -- Waiting for start; CLK idles high
        ST_START,   -- CLK pulled low for one half-period to initiate transfer
        SHIFTING,   -- Clocking DATA_BITS serial bits from the encoder
        DONE,       -- All bits captured; assert valid for one cycle
        MONOFLOP    -- Inter-frame delay (>= 20 µs) before next read
    );

end package ssi_pkg;
