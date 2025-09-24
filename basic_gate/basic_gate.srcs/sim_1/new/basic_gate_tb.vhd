----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 15.09.2025 18:49:18
-- Design Name: 
-- Module Name: basic_gate_tb - Behavioral
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

entity basic_gate_tb is
--  Port ( );
end basic_gate_tb;

architecture Behavioral of basic_gate_tb is

component basic_gate is
   port(
       a : in STD_LOGIC;
       b : in STD_LOGIC;
       out_and : out STD_LOGIC;
       out_or  : out STD_LOGIC;
       out_not : out STD_LOGIC
   );
end component;

--- signal declaration --
    signal a, b : std_logic :='0';
    signal out_and, out_or, out_not : std_logic;
       
begin
-- Instantiate the Unit Under Test (UUT)
uut: basic_gate
     port map(
     a => a,
     b => b,
     out_and => out_and,
     out_or  => out_or,
     out_not => out_not
     );
     
-- Stimulus process
    stim_proc: process
    begin
        -- Test case 1: a='0', b='0'
        a <= '0';
        b <= '0';
        wait for 100 ns;
        assert (out_and = '0' and out_or = '0' and out_not = '1')
            report "Test failed for input 00" severity error;

        -- Test case 2: a='0', b='1'
        a <= '0';
        b <= '1';
        wait for 100 ns;
        assert (out_and = '0' and out_or = '1' and out_not = '0')
            report "Test failed for input 01" severity error;

        -- Test case 3: a='1', b='0'
        a <= '1';
        b <= '0';
        wait for 100 ns;
        assert (out_and = '0' and out_or = '1' and out_not = '1')
            report "Test failed for input 10" severity error;

        -- Test case 4: a='1', b='1'
        a <= '1';
        b <= '1';
        wait for 100 ns;
        assert (out_and = '1' and out_or = '1' and out_not = '0')
            report "Test failed for input 11" severity error;

        -- End simulation
        report "All tests completed successfully!";
        wait;
    end process;     

end Behavioral;
