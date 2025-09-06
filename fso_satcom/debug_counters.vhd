library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity debug_counters is
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;
        tx_event  : in  std_logic;
        rx_event  : in  std_logic;
        tx_count  : out std_logic_vector(15 downto 0);
        rx_count  : out std_logic_vector(15 downto 0)
    );
end debug_counters;

architecture rtl of debug_counters is
    signal tx_reg : unsigned(15 downto 0) := (others => '0');
    signal rx_reg : unsigned(15 downto 0) := (others => '0');
begin
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            tx_reg <= (others => '0');
            rx_reg <= (others => '0');
        elsif rising_edge(clk) then
            if tx_event = '1' then
                tx_reg <= tx_reg + 1;
            end if;
            if rx_event = '1' then
                rx_reg <= rx_reg + 1;
            end if;
        end if;
    end process;

    tx_count <= std_logic_vector(tx_reg);
    rx_count <= std_logic_vector(rx_reg);
end rtl;
