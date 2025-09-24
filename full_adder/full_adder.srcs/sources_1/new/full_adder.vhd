----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 15.09.2025 14:41:04
-- Design Name: 
-- Module Name: full_adder - Behavioral
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

entity full_adder is
    Port ( a     : in STD_LOGIC;
           b     : in STD_LOGIC;
           cin   : in STD_LOGIC;
           sum   : out STD_LOGIC;
           carry : out STD_LOGIC
          );
end full_adder;

architecture Behavioral of full_adder is

---- components declarations -------
component half_adder is
   Port (  a     : in STD_LOGIC;
           b     : in STD_LOGIC;
           sum   : out STD_LOGIC;
           carry : out STD_LOGIC
   );
end component;   
-- Internal signals
signal s1  : STD_LOGIC;  -- S output from first half adder
signal ca1 : STD_LOGIC;  -- Carry output from first half adder
signal ca2 : STD_LOGIC;  -- Carry output from second half adder

begin
---- components instantiation -----
-- First half adder: adds inputs a and b
ha1: half_adder port map (
    a => a,
    b => b,
    sum => s1,
    carry => ca1
);

-- Second half adder: adds sum1 and cin
ha2: half_adder port map (
    a => s1,
    b => cin,
    sum => sum,
    carry => ca2
);

-- Final carry is OR of both carry outputs
carry <= ca1 or ca2;

end Behavioral;
