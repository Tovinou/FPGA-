-- Error Correction Codec Component (Fixed Port Size)
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity error_correction_codec is
    generic (
        DATA_WIDTH    : integer := 32;
        PARITY_BITS   : integer := 8
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        encode_mode     : in  std_logic;
        data_in         : in  std_logic_vector(DATA_WIDTH + PARITY_BITS - 1 downto 0);
        data_in_valid   : in  std_logic;
        data_out        : out std_logic_vector(DATA_WIDTH + PARITY_BITS - 1 downto 0);
        data_out_valid  : out std_logic;
        error_detected  : out std_logic;
        error_corrected : out std_logic
    );
end error_correction_codec;

architecture rtl of error_correction_codec is
    constant CODEWORD_WIDTH : integer := DATA_WIDTH + PARITY_BITS;
    signal parity_calc      : std_logic_vector(PARITY_BITS-1 downto 0);
    signal syndrome         : std_logic_vector(PARITY_BITS-1 downto 0);
    signal corrected_data   : std_logic_vector(DATA_WIDTH-1 downto 0);
    
begin
    ecc_process: process(clk, rst_n)
        variable temp_parity : std_logic_vector(PARITY_BITS-1 downto 0);
        variable error_pos   : integer range 0 to CODEWORD_WIDTH - 1;
        variable j_plus_1    : unsigned(31 downto 0);
        variable power_of_2  : unsigned(31 downto 0);
        variable bitwise_and : unsigned(31 downto 0);
    begin
        if rst_n = '0' then
            data_out <= (others => '0');
            data_out_valid <= '0';
            error_detected <= '0';
            error_corrected <= '0';
            parity_calc <= (others => '0');
            syndrome <= (others => '0');
            corrected_data <= (others => '0');
            
        elsif rising_edge(clk) then
            if data_in_valid = '1' then
                if encode_mode = '1' then
                    -- Hamming code parity generation for encoding
                    for i in 0 to PARITY_BITS-1 loop
                        temp_parity(i) := '0';
                        power_of_2 := to_unsigned(2**i, 32);
                        for j in 0 to DATA_WIDTH-1 loop
                            j_plus_1 := to_unsigned(j + 1, 32);
                            bitwise_and := j_plus_1 and power_of_2;
                            if bitwise_and /= 0 then
                                temp_parity(i) := temp_parity(i) xor data_in(j);
                            end if;
                        end loop;
                    end loop;
                    parity_calc <= temp_parity;
                    data_out <= data_in(DATA_WIDTH-1 downto 0) & temp_parity;
                    data_out_valid <= '1';
                    error_detected <= '0';
                    error_corrected <= '0';
                    
                else
                    -- Hamming code syndrome calculation for decoding
                    for i in 0 to PARITY_BITS-1 loop
                        syndrome(i) <= '0';
                        power_of_2 := to_unsigned(2**i, 32);
                        for j in 0 to DATA_WIDTH-1 loop
                            j_plus_1 := to_unsigned(j + 1, 32);
                            bitwise_and := j_plus_1 and power_of_2;
                            if bitwise_and /= 0 then
                                syndrome(i) <= syndrome(i) xor data_in(j);
                            end if;
                        end loop;
                        -- Include parity bit in syndrome calculation
                        syndrome(i) <= syndrome(i) xor data_in(DATA_WIDTH + i);
                    end loop;
                    
                    -- Error correction based on syndrome
                    error_pos := to_integer(unsigned(syndrome));
                    corrected_data <= data_in(DATA_WIDTH-1 downto 0);
                    
                    if error_pos /= 0 and error_pos <= DATA_WIDTH then
                        -- Single bit error in data - correct it
                        error_detected <= '1';
                        error_corrected <= '1';
                        corrected_data(error_pos-1) <= not data_in(error_pos-1);
                    elsif error_pos > DATA_WIDTH then
                        -- Error in parity bits or uncorrectable error
                        error_detected <= '1';
                        error_corrected <= '0';
                    else
                        -- No error detected
                        error_detected <= '0';
                        error_corrected <= '0';
                    end if;
                    
                    data_out <= corrected_data & syndrome;
                    data_out_valid <= '1';
                end if;
            else
                data_out_valid <= '0';
            end if;
        end if;
    end process;

end rtl;