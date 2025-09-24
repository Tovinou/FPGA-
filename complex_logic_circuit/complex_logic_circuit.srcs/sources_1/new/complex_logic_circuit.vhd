----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 15.09.2025 20:05:16
-- Design Name: 
-- Module Name: complex_logic_circuit - Behavioral
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

entity complex_logic_circuit is
    Port ( 
        -- 4-bit input vectors
        a : in STD_LOGIC_VECTOR(3 downto 0);
        b : in STD_LOGIC_VECTOR(3 downto 0);
        
        -- Control inputs
        enable  : in STD_LOGIC;
        mode_sel: in STD_LOGIC_VECTOR(1 downto 0);
        
        -- Basic logic outputs
        out_and : out STD_LOGIC;
        out_or  : out STD_LOGIC;
        out_xor : out STD_LOGIC;
        out_not_a: out STD_LOGIC; 
        
        -- Arithmetic outputs
        sum       : out STD_LOGIC_VECTOR(4 downto 0);
        difference: out STD_LOGIC_VECTOR(3 downto 0);       
        
        -- Comparison outputs
        equal     : out STD_LOGIC;
        a_greater : out STD_LOGIC;
        b_greater : out STD_LOGIC;       
        
        -- Advanced outputs
        parity_a  : out STD_LOGIC;
        leading_zeros : out STD_LOGIC_VECTOR(2 downto 0);       
        
        -- Multiplexed output based on mode_sel
        mux_out   : out STD_LOGIC_VECTOR(3 downto 0);        
        
        -- Status flags
        overflow  : out STD_LOGIC;
        underflow : out STD_LOGIC;
        valid     : out STD_LOGIC
    );
end complex_logic_circuit;

architecture Behavioral of complex_logic_circuit is
    -- Internal signals
    signal a_unsigned : unsigned(3 downto 0);
    signal b_unsigned : unsigned(3 downto 0);
    signal sum_temp   : unsigned(4 downto 0);
    signal diff_temp  : unsigned(4 downto 0);
    
    -- For single-bit outputs
    signal and_result : STD_LOGIC_VECTOR(3 downto 0);
    signal or_result  : STD_LOGIC_VECTOR(3 downto 0);
    signal xor_result : STD_LOGIC_VECTOR(3 downto 0);
    signal not_result : STD_LOGIC_VECTOR(3 downto 0);
    
    -- Priority encoder signals
    signal priority_out   : STD_LOGIC_VECTOR(2 downto 0);
    signal priority_valid : STD_LOGIC;
    
    -- Priority encoder component
    component priority_encoder is
        port(
            input     : in STD_LOGIC_VECTOR(3 downto 0);
            output    : out STD_LOGIC_VECTOR(2 downto 0);
            valid_out : out STD_LOGIC
        );
    end component;
    
begin
    -- Instantiate the priority encoder
    pe_inst: priority_encoder
        port map(
            input => a,
            output => priority_out,
            valid_out => priority_valid
        );
    
    -- Type conversions
    a_unsigned <= unsigned(a);
    b_unsigned <= unsigned(b);
    
    -- Calculate all 4-bit operations
    and_result <= a and b;
    or_result  <= a or b;
    xor_result <= a xor b;
    not_result <= not a;
    
    -- Basic bitwise operations (output only the MSB)
    out_and <= and_result(3) when enable = '1' else '0';
    out_or  <= or_result(3) when enable = '1' else '0';
    out_xor <= xor_result(3) when enable = '1' else '0';
    out_not_a <= not_result(3) when enable = '1' else '0';
    
    -- Arithmetic operations
    sum_temp <= resize(a_unsigned, 5) + resize(b_unsigned, 5);
    sum <= std_logic_vector(sum_temp) when enable = '1' else (others => '0');
    
    -- Subtraction
    diff_temp <= resize(a_unsigned, 5) - resize(b_unsigned, 5);
    difference <= std_logic_vector(diff_temp(3 downto 0)) when enable = '1' else (others => '0');
    
    -- Comparison operations
    equal <= '1' when (a = b and enable = '1') else '0';
    a_greater <= '1' when (a_unsigned > b_unsigned and enable = '1') else '0';
    b_greater <= '1' when (b_unsigned > a_unsigned and enable = '1') else '0';
    
    -- Parity calculation (even parity)
    parity_a <= (a(0) xor a(1) xor a(2) xor a(3)) when enable = '1' else '0';
    
    -- Use priority encoder for leading zeros
    leading_zeros <= priority_out when enable = '1' else (others => '0');
    
    -- Mode-based multiplexer
    process(mode_sel, enable, and_result, or_result, xor_result, not_result)
    begin
        if enable = '1' then
            case mode_sel is
                when "00" => mux_out <= and_result;
                when "01" => mux_out <= or_result;
                when "10" => mux_out <= xor_result;
                when "11" => mux_out <= not_result;
                when others => mux_out <= (others => '0');
            end case;
        else
            mux_out <= (others => '0');
        end if;
    end process;
    
    -- Status flags
    overflow <= '1' when (enable = '1' and sum_temp(4) = '1') else '0';
    underflow <= '1' when (enable = '1' and a_unsigned < b_unsigned) else '0';
    valid <= enable;

end Behavioral;

-- Priority Encoder Implementation
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity priority_encoder is
    port(
        input     : in STD_LOGIC_VECTOR(3 downto 0);
        output    : out STD_LOGIC_VECTOR(2 downto 0);
        valid_out : out STD_LOGIC
    );
end priority_encoder;

architecture Behavioral of priority_encoder is
begin
    process(input)
    begin
        valid_out <= '1';
        case input is
            when "1XXX" => output <= "000";  -- MSB is 1
            when "01XX" => output <= "001";  -- Second bit is 1
            when "001X" => output <= "010";  -- Third bit is 1
            when "0001" => output <= "011";  -- LSB is 1
            when "0000" => 
                output <= "100";  -- All zeros
                valid_out <= '0';
            when others => 
                output <= "111";  -- Error case
                valid_out <= '0';
        end case;
    end process;
end Behavioral;