library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity deserializer is
    generic (
        WIDTH : integer := 40
    );
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;
        serial_in : in  std_logic;
        valid_in  : in  std_logic; -- when 1, new serial bit available
        data_out  : out std_logic_vector(WIDTH-1 downto 0);
        valid_out : out std_logic
    );
end deserializer;

architecture rtl of deserializer is
    signal shift_reg  : std_logic_vector(WIDTH-1 downto 0) := (others => '0');
    signal bit_count  : integer range 0 to WIDTH := 0;
begin
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            shift_reg <= (others => '0');
            bit_count <= 0;
            data_out <= (others => '0');
            valid_out <= '0';
        elsif rising_edge(clk) then
            if valid_in = '1' then
                shift_reg <= shift_reg(WIDTH-2 downto 0) & serial_in;
                bit_count <= bit_count + 1;
                if bit_count = WIDTH-1 then
                    data_out <= shift_reg;
                    valid_out <= '1';
                    bit_count <= 0;
                else
                    valid_out <= '0';
                end if;
            end if;
        end if;
    end process;
end rtl;
