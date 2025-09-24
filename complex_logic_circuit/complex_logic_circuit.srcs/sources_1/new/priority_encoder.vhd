----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 16.09.2025 09:09:11
-- Design Name: 
-- Module Name: priority_encoder - Behavioral
-- Project Name:Priority Encoder 
-- Target Devices: 
-- Tool Versions: 
-- Description:4-to-3 Priority Encoder
--             Encodes the position of the highest priority (MSB) active bit
--             Priority: input(3) > input(2) > input(1) > input(0) 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity priority_encoder is
    Port ( 
        input     : in STD_LOGIC_VECTOR(3 downto 0);   -- 4-bit input
        output    : out STD_LOGIC_VECTOR(2 downto 0);  -- 3-bit encoded output
        valid_out : out STD_LOGIC                      -- Valid output flag
    );
end priority_encoder;

architecture Behavioral of priority_encoder is
begin
    process(input)
    begin
        -- Default values
        output <= "000";
        valid_out <= '0';
        
        -- Priority encoding (highest bit has highest priority)
        if input(3) = '1' then
            output <= "011";      -- Position 3 (binary 11)
            valid_out <= '1';
        elsif input(2) = '1' then
            output <= "010";      -- Position 2 (binary 10)
            valid_out <= '1';
        elsif input(1) = '1' then
            output <= "001";      -- Position 1 (binary 01)
            valid_out <= '1';
        elsif input(0) = '1' then
            output <= "000";      -- Position 0 (binary 00)
            valid_out <= '1';
        else
            -- No input is active
            output <= "000";
            valid_out <= '0';     -- Invalid output
        end if;
    end process;
end Behavioral;

----------------------------------------------------------------------------------
-- Alternative implementation using concurrent statements
----------------------------------------------------------------------------------
-- architecture Concurrent of priority_encoder is
-- begin
--     -- Priority encoding using conditional assignments
--     output <= "011" when input(3) = '1' else
--               "010" when input(2) = '1' else  
--               "001" when input(1) = '1' else
--               "000" when input(0) = '1' else
--               "000";
--     
--     -- Valid when any input bit is active
--     valid_out <= '1' when (input /= "0000") else '0';
-- end Concurrent;
