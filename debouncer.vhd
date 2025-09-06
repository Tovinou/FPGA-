-- Free Space Optical Satellite Communication System
-- Top-level FPGA design for satellite optical communication
-- Author: FPGA Engineer Komlan Tovinou
-- Adapted for Intel MAX10 DE10-Lite FPGA Board
-- Date: 2025-08-30
-- Target: DE10-Lite with 50MHz onboard oscillator

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Debouncer module for two key inputs
entity debouncer is
    generic (
        DEBOUNCE_LIMIT : integer := 1000000 -- ~20ms at 50MHz
    );
    port (
        clk          : in  std_logic;                    -- Clock input
        rst_n        : in  std_logic;                    -- Active-low reset
        key_in       : in  std_logic_vector(1 downto 0); -- Raw key inputs (active-low)
        key_debounced: out std_logic_vector(1 downto 0)  -- Debounced key outputs (active-high)
    );
end debouncer;

architecture behavioral of debouncer is
begin
    process (clk, rst_n)
        variable debounce_cnt0, debounce_cnt1 : integer range 0 to DEBOUNCE_LIMIT := 0;
    begin
        if rst_n = '0' then
            key_debounced <= (others => '0');
            debounce_cnt0 := 0;
            debounce_cnt1 := 0;
        elsif rising_edge(clk) then
            -- Debounce key_in(0)
            if key_in(0) = '0' and debounce_cnt0 < DEBOUNCE_LIMIT then
                debounce_cnt0 := debounce_cnt0 + 1;
                if debounce_cnt0 = DEBOUNCE_LIMIT then
                    key_debounced(0) <= '1'; -- Active high when pressed
                end if;
            elsif key_in(0) = '1' then
                debounce_cnt0 := 0;
                key_debounced(0) <= '0';
            end if;
            -- Debounce key_in(1)
            if key_in(1) = '0' and debounce_cnt1 < DEBOUNCE_LIMIT then
                debounce_cnt1 := debounce_cnt1 + 1;
                if debounce_cnt1 = DEBOUNCE_LIMIT then
                    key_debounced(1) <= '1'; -- Active high when pressed
                end if;
            elsif key_in(1) = '1' then
                debounce_cnt1 := 0;
                key_debounced(1) <= '0';
            end if;
        end if;
    end process;
end behavioral;