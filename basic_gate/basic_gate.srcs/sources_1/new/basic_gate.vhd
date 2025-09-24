----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 15.09.2025 18:40:17
-- Design Name: Komlan
-- Module Name: basic_gate - Behavioral
-- Project Name: Basic gate
-- Target Devices: 
-- Tool Versions: 
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

entity basic_gate is
    Port ( a : in STD_LOGIC;
           b : in STD_LOGIC;
           out_and : out STD_LOGIC; 
           out_or  : out STD_LOGIC; 
           out_not : out STD_LOGIC
    );
end basic_gate;

architecture Behavioral of basic_gate is

begin
   out_and <= a and b;
   out_or  <= a or b;
   out_not <= not b;


end Behavioral;
