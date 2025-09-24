----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 15.09.2025 12:41:35
-- Design Name: 
-- Module Name: comparator_tb - Behavioral
-- Project Name: 
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

entity comparator_tb is
    
end comparator_tb;

architecture Behavioral of comparator_tb is
   component comparator port(
      a : in STD_LOGIC;
      b : in STD_LOGIC;
      y : out STD_LOGIC_VECTOR(1 downto 0)
   );
   end component;
   
   signal a : std_logic := '0';
   signal b : std_logic := '0';
   signal y : std_logic_vector(1 downto 0);
   
begin
   uut : comparator port map (
       a => a,
       b => b,
       y => y
   );
   
   stim_proc: process
   begin
      wait for 100 ns;
    a <= '0'; 
    b <= '1';
    wait for 100 ns;
    a <= '1'; 
    b <= '0';
    wait for 100 ns;
    a <= '0'; 
    b <= '0';
    wait for 100 ns;
    a <= '1'; 
    b <= '1';  
    wait for 100 ns;
    wait;  -- Stop the process
   end process;
      
end Behavioral;
