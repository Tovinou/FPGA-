----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 15.09.2025 12:31:53
-- Design Name: Komlan
-- Module Name: comparator - Behavioral
-- Project Name: comparator
-- Target Devices: 
-- Tool Versions: vivado
-- Description: 
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity comparator is
    Port ( a : in STD_LOGIC;
           b : in STD_LOGIC;
           y : out STD_LOGIC_VECTOR(1 downto 0)
           );
end comparator;

architecture Behavioral of comparator is

begin
    
    process(a,b)
    begin
       if(a < b) then
          y <= "00";
          else if (a = b) then
          y <= "01";
          else y <= "10";
          end if;
       end if;   
    end process;
    
end Behavioral;
