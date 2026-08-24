-- =============================================================================
-- debounce_explicit.vhd
-- Button/switch debouncer for DE10-Lite push buttons
-- Uses explicit counter-based approach (no shift register)
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity debounce_explicit is
    generic (
        CLK_FREQ_HZ  : integer := 50_000_000;  -- 50 MHz
        DEBOUNCE_MS  : integer := 20            -- 20ms debounce window
    );
    port (
        clk      : in  std_logic;
        rst_n    : in  std_logic;
        btn_in   : in  std_logic;   -- raw button input (active low on DE10-Lite)
        btn_out  : out std_logic;   -- debounced, active-high pulse
        btn_level: out std_logic    -- debounced level output
    );
end entity debounce_explicit;

architecture rtl of debounce_explicit is

    constant DEBOUNCE_CYCLES : integer :=
        (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;  -- = 1,000,000 @ 50MHz, 20ms

    signal cnt      : integer range 0 to DEBOUNCE_CYCLES := 0;
    signal btn_sync1: std_logic := '1';
    signal btn_sync2: std_logic := '1';
    signal btn_prev : std_logic := '1';
    signal stable   : std_logic := '1';

begin

    -- -------------------------------------------------------------------------
    -- 2-FF synchroniser (metastability protection)
    -- -------------------------------------------------------------------------
    p_sync : process(clk)
    begin
        if rising_edge(clk) then
            btn_sync1 <= btn_in;
            btn_sync2 <= btn_sync1;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- Counter-based debounce
    -- -------------------------------------------------------------------------
    p_debounce : process(clk, rst_n)
    begin
        if rst_n = '0' then
            cnt     <= 0;
            stable  <= '1';
            btn_prev <= '1';
            btn_out  <= '0';
            btn_level <= '1';

        elsif rising_edge(clk) then
            btn_out <= '0';

            if btn_sync2 /= stable then
                -- Input differs from stable state: count
                if cnt = DEBOUNCE_CYCLES - 1 then
                    if btn_prev = '1' and btn_sync2 = '0' then
                        btn_out <= '1';
                    end if;
                    btn_prev  <= btn_sync2;
                    stable    <= btn_sync2;
                    btn_level <= btn_sync2;
                    cnt <= 0;
                else
                    cnt <= cnt + 1;
                end if;
            else
                cnt <= 0;
            end if;
        end if;
    end process;

end architecture rtl;
