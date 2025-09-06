library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- PLL/Clock Divider Emulation for MAX10
entity pll_clocks is
    port (
        clk_in_50mhz : in  std_logic;   -- DE10-Lite onboard 50 MHz clock
        rst_n        : in  std_logic;   -- Active-low reset
        clk_25mhz    : out std_logic;   -- For data processing
        clk_1mhz     : out std_logic;   -- For laser modulation
        locked       : out std_logic    -- Simple lock emulation
    );
end pll_clocks;

architecture rtl of pll_clocks is
    signal div2_counter : std_logic := '0';          -- ÷2 → 25 MHz
    signal div25_cnt    : unsigned(4 downto 0) := (others => '0'); -- ÷25 → 1 MHz
    signal clk25_int    : std_logic := '0';
    signal clk1_int     : std_logic := '0';
    signal lock_counter : unsigned(15 downto 0) := (others => '0');
    signal pll_locked   : std_logic := '0';
begin
    process(clk_in_50mhz, rst_n)
    begin
        if rst_n = '0' then
            div2_counter <= '0';
            div25_cnt    <= (others => '0');
            clk25_int    <= '0';
            clk1_int     <= '0';
            lock_counter <= (others => '0');
            pll_locked   <= '0';
        elsif rising_edge(clk_in_50mhz) then
            -- Generate 25 MHz (divide by 2)
            div2_counter <= not div2_counter;
            clk25_int    <= div2_counter;
            -- Generate 1 MHz (divide by 25 * 2 = 50)
            if div25_cnt = 24 then
                div25_cnt <= (others => '0');
                clk1_int  <= not clk1_int;
            else
                div25_cnt <= div25_cnt + 1;
            end if;
            -- Fake PLL lock signal (assert after some cycles)
            if lock_counter < 65535 then
                lock_counter <= lock_counter + 1;
            else
                pll_locked <= '1';
            end if;
        end if;
    end process;
    -- Output assignments
    clk_25mhz <= clk25_int;
    clk_1mhz  <= clk1_int;
    locked    <= pll_locked;
end rtl;