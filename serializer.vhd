library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity serializer is
    generic (
        WIDTH : integer := 40
    );
    port (
        clk      : in  std_logic;
        rst_n    : in  std_logic;
        data_in  : in  std_logic_vector(WIDTH-1 downto 0);
        valid_in : in  std_logic;
        data_out : out std_logic
    );
end serializer;

architecture rtl of serializer is
    signal shift_reg  : std_logic_vector(WIDTH-1 downto 0) := (others => '0');
    signal bit_count  : integer range 0 to WIDTH := 0;
begin
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            shift_reg <= (others => '0');
            bit_count <= 0;
            data_out <= '0';
        elsif rising_edge(clk) then
            if valid_in = '1' then
                shift_reg <= data_in;
                bit_count <= 0;
            elsif bit_count < WIDTH then
                data_out <= shift_reg(WIDTH-1);
                shift_reg <= shift_reg(WIDTH-2 downto 0) & '0';
                bit_count <= bit_count + 1;
            end if;
        end if;
    end process;
end rtl;
