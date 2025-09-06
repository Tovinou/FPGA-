library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Test data generator module
entity test_data_generator is
    generic (
        DATA_WIDTH : integer := 32
    );
    port (
        clk        : in  std_logic;                    -- Clock input
        rst_n      : in  std_logic;                    -- Active-low reset
        data_valid : in  std_logic;                    -- Enable counter increment
        data_out   : out std_logic_vector(DATA_WIDTH-1 downto 0) -- Test data output
    );
end test_data_generator;

architecture behavioral of test_data_generator is
    signal counter : unsigned(DATA_WIDTH-1 downto 0) := (others => '0');
begin
    process (clk, rst_n)
    begin
        if rst_n = '0' then
            counter <= (others => '0');
        elsif rising_edge(clk) then
            if data_valid = '1' then
                counter <= counter + 1;
            end if;
        end if;
    end process;
    data_out <= std_logic_vector(counter);
end behavioral;