----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 16.09.2025 09:59:37
-- Design Name: 
-- Module Name: complex_logic_circuit_tb - Behavioral
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
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL; -- For file operations if needed

entity complex_logic_circuit_tb is
--  Port ( );
end complex_logic_circuit_tb;

architecture Behavioral of complex_logic_circuit_tb is
    -- Component declaration (updated to match the actual entity)
    component complex_logic_circuit is
        port(
            a : in STD_LOGIC_VECTOR(3 downto 0);  -- Changed to 4-bit vector
            b : in STD_LOGIC_VECTOR(3 downto 0);  -- Changed to 4-bit vector
            enable  : in STD_LOGIC;
            mode_sel: in STD_LOGIC_VECTOR(1 downto 0);  -- Changed to 2-bit vector
            out_and : out STD_LOGIC;  -- Changed to single bit
            out_or  : out STD_LOGIC;  -- Changed to single bit
            out_xor : out STD_LOGIC;  -- Changed to single bit and fixed name
            out_not_a: out STD_LOGIC; -- Changed to single bit
            sum       : out STD_LOGIC_VECTOR(4 downto 0);
            difference: out STD_LOGIC_VECTOR(3 downto 0);       
            equal     : out STD_LOGIC;
            a_greater : out STD_LOGIC;
            b_greater : out STD_LOGIC;       
            parity_a  : out STD_LOGIC;
            leading_zeros : out STD_LOGIC_VECTOR(2 downto 0);       
            mux_out   : out STD_LOGIC_VECTOR(3 downto 0);        
            overflow  : out STD_LOGIC;
            underflow : out STD_LOGIC;
            valid     : out STD_LOGIC
        );
    end component;
 
    -- Test signals
    signal a_tb : STD_LOGIC_VECTOR(3 downto 0) := "0000";
    signal b_tb : STD_LOGIC_VECTOR(3 downto 0) := "0000";
    signal enable_tb : STD_LOGIC := '0';
    signal mode_sel_tb : STD_LOGIC_VECTOR(1 downto 0) := "00";    
    -- Output signals
    signal out_and_tb : STD_LOGIC;
    signal out_or_tb : STD_LOGIC;
    signal out_xor_tb : STD_LOGIC;
    signal out_not_a_tb : STD_LOGIC;
    signal sum_tb : STD_LOGIC_VECTOR(4 downto 0);
    signal difference_tb : STD_LOGIC_VECTOR(3 downto 0);
    signal equal_tb : STD_LOGIC;
    signal a_greater_tb : STD_LOGIC;
    signal b_greater_tb : STD_LOGIC;
    signal parity_a_tb : STD_LOGIC;
    signal leading_zeros_tb : STD_LOGIC_VECTOR(2 downto 0);
    signal mux_out_tb : STD_LOGIC_VECTOR(3 downto 0);
    signal overflow_tb : STD_LOGIC;
    signal underflow_tb : STD_LOGIC;
    signal valid_tb : STD_LOGIC;

    -- Helper function to convert std_logic_vector to string
    function to_string(slv : std_logic_vector) return string is
        variable result : string(1 to slv'length);
        variable i : integer;
    begin
        i := 1;
        for idx in slv'range loop
            case slv(idx) is
                when 'U' => result(i) := 'U';
                when 'X' => result(i) := 'X';
                when '0' => result(i) := '0';
                when '1' => result(i) := '1';
                when 'Z' => result(i) := 'Z';
                when 'W' => result(i) := 'W';
                when 'L' => result(i) := 'L';
                when 'H' => result(i) := 'H';
                when '-' => result(i) := '-';
            end case;
            i := i + 1;
        end loop;
        return result;
    end function;
   
begin
    -- Unit under test instantiation
    uut: complex_logic_circuit port map (
        a => a_tb,
        b => b_tb,
        enable => enable_tb,
        mode_sel => mode_sel_tb,
        out_and => out_and_tb,
        out_or => out_or_tb,
        out_xor => out_xor_tb,
        out_not_a => out_not_a_tb,
        sum => sum_tb,
        difference => difference_tb,
        equal => equal_tb,
        a_greater => a_greater_tb,
        b_greater => b_greater_tb,
        parity_a => parity_a_tb,
        leading_zeros => leading_zeros_tb,
        mux_out => mux_out_tb,
        overflow => overflow_tb,
        underflow => underflow_tb,
        valid => valid_tb
    );
    
    -- Main stimulus process
    stim_proc: process
    begin
        -- Test 1: Disabled state (enable = '0')
        report "=== Test 1: Disabled State ===";
        enable_tb <= '0';
        a_tb <= "1010";
        b_tb <= "1100";
        wait for 20 ns;
        
        -- Test 2: Enable the circuit
        report "=== Test 2: Basic Logic Operations ===";
        enable_tb <= '1';
        a_tb <= "1010";  -- 10 in decimal
        b_tb <= "1100";  -- 12 in decimal
        wait for 20 ns;
        
        -- Test 3: Test arithmetic operations
        report "=== Test 3: Arithmetic Operations ===";
        a_tb <= "0101";  -- 5 in decimal
        b_tb <= "0011";  -- 3 in decimal
        wait for 20 ns;
        
        -- Test 4: Test overflow condition
        report "=== Test 4: Overflow Test ===";
        a_tb <= "1111";  -- 15 in decimal
        b_tb <= "0001";  -- 1 in decimal (15+1=16, overflow for 4-bit)
        wait for 20 ns;
        
        -- Test 5: Test underflow condition
        report "=== Test 5: Underflow Test ===";
        a_tb <= "0010";  -- 2 in decimal
        b_tb <= "0101";  -- 5 in decimal (2-5=-3, underflow)
        wait for 20 ns;
        
        -- Test 6: Test equality
        report "=== Test 6: Equality Test ===";
        a_tb <= "0110";  -- 6 in decimal
        b_tb <= "0110";  -- 6 in decimal
        wait for 20 ns;
        
        -- Test 7: Test leading zeros with different patterns
        report "=== Test 7: Leading Zeros Test ===";
        a_tb <= "0001";  -- 3 leading zeros
        b_tb <= "0000";
        wait for 20 ns;
        
        a_tb <= "0010";  -- 2 leading zeros
        wait for 20 ns;
        
        a_tb <= "0100";  -- 1 leading zero
        wait for 20 ns;
        
        a_tb <= "1000";  -- 0 leading zeros
        wait for 20 ns;
        
        a_tb <= "0000";  -- 4 leading zeros (all zeros)
        wait for 20 ns;
        
        -- Test 8: Test parity (even parity check)
        report "=== Test 8: Parity Test ===";
        a_tb <= "0011";  -- 2 ones -> even parity = 0
        wait for 20 ns;
        
        a_tb <= "0111";  -- 3 ones -> even parity = 1
        wait for 20 ns;
        
        -- Test 9: Test multiplexer modes
        report "=== Test 9: Multiplexer Test ===";
        a_tb <= "1010";
        b_tb <= "1100";
        
        mode_sel_tb <= "00";  -- AND output
        wait for 15 ns;
        
        mode_sel_tb <= "01";  -- OR output
        wait for 15 ns;
        
        mode_sel_tb <= "10";  -- XOR output
        wait for 15 ns;
        
        mode_sel_tb <= "11";  -- NOT_A output
        wait for 15 ns;
        
        -- Test 10: Edge cases
        report "=== Test 10: Edge Cases ===";
        a_tb <= "0000";
        b_tb <= "0000";
        mode_sel_tb <= "00";
        wait for 20 ns;
        
        a_tb <= "1111";
        b_tb <= "1111";
        wait for 20 ns;
        
        -- Test 11: Disable and re-enable
        report "=== Test 11: Disable/Enable Test ===";
        enable_tb <= '0';
        wait for 20 ns;
        
        enable_tb <= '1';
        wait for 20 ns;
        
        report "=== All Tests Completed ===";
        wait;
    end process;
    
    -- Monitor process to display key results
    monitor: process
    begin
        wait for 1 ns; -- Wait a small delta time to ensure signals are updated
        
        if enable_tb = '1' then
            report "Inputs: a=" & to_string(a_tb) & ", b=" & to_string(b_tb) & 
                   " | Sum=" & to_string(sum_tb) & 
                   " | Diff=" & to_string(difference_tb) &
                   " | Equal=" & std_logic'image(equal_tb) &
                   " | Overflow=" & std_logic'image(overflow_tb) &
                   " | Underflow=" & std_logic'image(underflow_tb) &
                   " | Parity_a=" & std_logic'image(parity_a_tb) &
                   " | Leading_zeros=" & to_string(leading_zeros_tb);
        end if;
        
        wait on a_tb, b_tb, enable_tb; -- Sensitivity list
    end process;

end Behavioral;