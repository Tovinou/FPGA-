----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 15.09.2025 15:24:20
-- Design Name: 
-- Module Name: full_adder_tb - Behavioral
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

entity full_adder_tb is   
end full_adder_tb;

architecture Behavioral of full_adder_tb is
    --- components declarations ---
    component full_adder is
        Port (  a     : in STD_LOGIC;
                b     : in STD_LOGIC;
                cin   : in STD_LOGIC;
                sum   : out STD_LOGIC;
                carry : out STD_LOGIC
        );
    end component;  
    
    -- Test signals
    signal a     : STD_LOGIC := '0';
    signal b     : STD_LOGIC := '0';
    signal cin   : STD_LOGIC := '0';
    signal sum   : STD_LOGIC;
    signal carry : STD_LOGIC;
      
begin
    --- unit under test instantiation ----
    uut: full_adder port map(
        a => a,
        b => b,
        cin => cin,
        sum => sum,
        carry => carry
    );
  
    --- Stimulus process ---
    stim_proc: process
    begin
        -- Test all possible input combinations
        -- Test case 0: a=0, b=0, cin=0
        a <= '0'; b <= '0'; cin <= '0';
        wait for 50 ns;
        
        -- Test case 1: a=0, b=0, cin=1
        a <= '0'; b <= '0'; cin <= '1';
        wait for 50 ns;
        
        -- Test case 2: a=0, b=1, cin=0
        a <= '0'; b <= '1'; cin <= '0';
        wait for 10 ns;
        
        -- Test case 3: a=0, b=1, cin=1
        a <= '0'; b <= '1'; cin <= '1';
        wait for 50 ns;
        
        -- Test case 4: a=1, b=0, cin=0
        a <= '1'; b <= '0'; cin <= '0';
        wait for 10 ns;
        
        -- Test case 5: a=1, b=0, cin=1
        a <= '1'; b <= '0'; cin <= '1';
        wait for 10 ns;
        
        -- Test case 6: a=1, b=1, cin=0
        a <= '1'; b <= '1'; cin <= '0';
        wait for 50 ns;
        
        -- Test case 7: a=1, b=1, cin=1
        a <= '1'; b <= '1'; cin <= '1';
        wait for 50 ns;
        
        -- End simulation
       -- wait;
    end process;
    
    -- Optional: Monitor process to display results
    monitor: process(a, b, cin, sum, carry)
    begin
        report "a=" & std_logic'image(a) & 
               ", b=" & std_logic'image(b) & 
               ", cin=" & std_logic'image(cin) & 
               " => sum=" & std_logic'image(sum) & 
               ", carry=" & std_logic'image(carry);
    end process;
        
end Behavioral;
