-- =============================================================================
-- ssi_clk_out.vhd
-- SSI Clock Output Driver
--
-- Drives the physical ssi_clk pin according to FSM state:
--
--   IDLE / DONE / MONOFLOP : ssi_clk = '1'  (bus idles high)
--   ST_START               : ssi_clk = '0'  (pulled low to begin transfer)
--   SHIFTING               : ssi_clk toggles on every clk_en pulse
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.ssi_pkg.all;

entity ssi_clk_out is
    port (
        clk     : in  std_logic;
        rst_n   : in  std_logic;
        -- From FSM
        state   : in  t_ssi_state;
        clk_en  : in  std_logic;   -- Half-period tick from ssi_clk_div
        -- Physical pin
        ssi_clk : out std_logic
    );
end entity ssi_clk_out;

architecture rtl of ssi_clk_out is

    signal ssi_clk_r : std_logic;

begin

    p_clk_out : process (clk, rst_n)
    begin
        if rst_n = '0' then
            ssi_clk_r <= '1';           -- Idle high on reset
        elsif rising_edge(clk) then
            case state is

                when IDLE | DONE | MONOFLOP =>
                    ssi_clk_r <= '1';

                when ST_START =>
                    ssi_clk_r <= '0';   -- Pull low to initiate transfer

                when SHIFTING =>
                    if clk_en = '1' then
                        ssi_clk_r <= not ssi_clk_r;
                    end if;

            end case;
        end if;
    end process p_clk_out;

    ssi_clk <= ssi_clk_r;

end architecture rtl;
