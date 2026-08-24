-- =============================================================================
-- ssi_clk_div.vhd
-- SSI Clock Divider
--
-- Generates a half-period enable pulse (clk_en) whenever the internal counter
-- reaches (CLK_FREQ_HZ / (SSI_CLK_HZ * 2)) - 1.
-- The counter only runs while 'active' is asserted (START + SHIFTING states).
-- Between frames the counter is reset to zero so the first half-period after
-- START is always a full width.
--
-- Generic defaults match the DE10-Lite (50 MHz) running SSI at 500 kHz.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;          -- for log2 / ceil at elaboration time

entity ssi_clk_div is
    generic (
        CLK_FREQ_HZ : positive := 50_000_000;  -- System clock frequency
        SSI_CLK_HZ  : positive := 500_000       -- Desired SSI clock frequency
    );
    port (
        clk    : in  std_logic;
        rst_n  : in  std_logic;
        active : in  std_logic;   -- HIGH when FSM is in START or SHIFTING
        clk_en : out std_logic    -- Single-cycle high-pulse every SSI half-period
    );
end entity ssi_clk_div;

architecture rtl of ssi_clk_div is

    -- Number of system clocks per SSI half-period
    constant C_DIV   : positive := CLK_FREQ_HZ / (SSI_CLK_HZ * 2);
    constant C_DIV_W : positive := integer(ceil(log2(real(C_DIV + 1))));

    signal cnt    : unsigned(C_DIV_W - 1 downto 0);
    signal clk_en_i : std_logic;

begin

    p_div : process (clk, rst_n)
    begin
        if rst_n = '0' then
            cnt      <= (others => '0');
            clk_en_i <= '0';
        elsif rising_edge(clk) then
            clk_en_i <= '0';                    -- default: de-assert
            if active = '1' then
                if cnt = to_unsigned(C_DIV - 1, C_DIV_W) then
                    cnt      <= (others => '0');
                    clk_en_i <= '1';            -- pulse for one sys-clock cycle
                else
                    cnt <= cnt + 1;
                end if;
            else
                cnt <= (others => '0');         -- reset counter when idle
            end if;
        end if;
    end process p_div;

    clk_en <= clk_en_i;

end architecture rtl;
