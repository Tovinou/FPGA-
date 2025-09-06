library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity seven_segment_decoder is
    generic (
        SLICE_OFFSET : integer := 0  -- Specifies the 4-bit slice to select (0 for HEX0, 4 for HEX1, etc.)
    );
    port (
        display_mode     : in  std_logic_vector(2 downto 0);
        rx_data_out      : in  std_logic_vector(23 downto 0);
        link_quality     : in  std_logic_vector(7 downto 0);
        bit_error_rate   : in  std_logic_vector(15 downto 0);
        rx_error_corrected : in  std_logic;
        debug_signals    : in  std_logic_vector(23 downto 0);
        enable           : in  std_logic;
        segments         : out std_logic_vector(6 downto 0)
    );
end seven_segment_decoder;

architecture behavioral of seven_segment_decoder is
    -- Define a type for the segment lookup table
    type seg_array_t is array (0 to 15) of std_logic_vector(6 downto 0);
    -- Constant for segment patterns
    constant SEG_TABLE : seg_array_t := (
        "1000000", -- 0
        "1111001", -- 1
        "0100100", -- 2
        "0110000", -- 3
        "0011001", -- 4
        "0010010", -- 5
        "0000010", -- 6
        "1111000", -- 7
        "0000000", -- 8
        "0010000", -- 9
        "0001000", -- A
        "0000011", -- b
        "1000110", -- C
        "0100001", -- d
        "0000110", -- E
        "0001110"  -- F
    );
    signal selected_data : std_logic_vector(3 downto 0);
begin
    -- Select the appropriate 4-bit data based on display_mode
    process(display_mode, rx_data_out, link_quality, bit_error_rate, rx_error_corrected, debug_signals)
    begin
        case display_mode is
            when "011" =>
                if SLICE_OFFSET + 3 <= 23 then
                    selected_data <= rx_data_out(SLICE_OFFSET + 3 downto SLICE_OFFSET);
                else
                    selected_data <= "0000"; -- Fallback if slice is out of range
                end if;
            when "001" =>
                if SLICE_OFFSET + 3 <= 7 then
                    selected_data <= link_quality(SLICE_OFFSET + 3 downto SLICE_OFFSET);
                else
                    selected_data <= link_quality(3 downto 0); -- Use only the least significant 4 bits
                end if;
            when "010" =>
                if SLICE_OFFSET + 3 <= 15 then
                    selected_data <= bit_error_rate(SLICE_OFFSET + 3 downto SLICE_OFFSET);
                else
                    selected_data <= bit_error_rate(3 downto 0); -- Use only the least significant 4 bits
                end if;
            when "100" =>
                selected_data <= "000" & rx_error_corrected;
            when others =>
                if SLICE_OFFSET + 3 <= 23 then
                    selected_data <= debug_signals(SLICE_OFFSET + 3 downto SLICE_OFFSET);
                else
                    selected_data <= debug_signals(3 downto 0); -- Use only the least significant 4 bits
                end if;
        end case;
    end process;

    -- Decode the selected data to 7-segment output
    process(selected_data, enable)
    begin
        if enable = '1' then
            segments <= SEG_TABLE(to_integer(unsigned(selected_data)));
        else
            segments <= "1111111"; -- All segments off
        end if;
    end process;
end behavioral;