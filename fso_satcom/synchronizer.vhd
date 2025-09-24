library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Synchronizer module for two signals
entity synchronizer is
    port (
        clk      : in  std_logic;                    -- Destination clock
        rst_n    : in  std_logic;                    -- Active-low reset
        data_in  : in  std_logic_vector(1 downto 0); -- Input signals to synchronize
        data_out : out std_logic_vector(1 downto 0)  -- Synchronized output signals
    );
end synchronizer;

architecture behavioral of synchronizer is
    signal sync_stage1 : std_logic_vector(1 downto 0);
    signal sync_stage2 : std_logic_vector(1 downto 0);
begin
    process (clk, rst_n)
    begin
        if rst_n = '0' then
            sync_stage1 <= (others => '0');
            sync_stage2 <= (others => '0');
        elsif rising_edge(clk) then
            sync_stage1 <= data_in;
            sync_stage2 <= sync_stage1;
        end if;
    end process;
    data_out <= sync_stage2;
end behavioral;