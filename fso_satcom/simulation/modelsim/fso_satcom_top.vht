-- Copyright (C) 2018  Intel Corporation. All rights reserved.
-- Your use of Intel Corporation's design tools, logic functions 
-- and other software and tools, and its AMPP partner logic 
-- functions, and any output files from any of the foregoing 
-- (including device programming or simulation files), and any 
-- associated documentation or information are expressly subject 
-- to the terms and conditions of the Intel Program License 
-- Subscription Agreement, the Intel Quartus Prime License Agreement,
-- the Intel FPGA IP License Agreement, or other applicable license
-- agreement, including, without limitation, that your use is for
-- the sole purpose of programming logic devices manufactured by
-- Intel and sold by Intel or its authorized distributors.  Please
-- refer to the applicable agreement for further details.

-- ***************************************************************************
-- This file contains a Vhdl test bench template that is freely editable to   
-- suit user's needs .Comments are provided in each section to help the user  
-- fill out necessary details.                                                
-- ***************************************************************************
-- Generated on "08/31/2025 13:55:44"
                                                            
-- Vhdl Test Bench template for design  :  fso_satcom_top
-- 
-- Simulation tool : ModelSim-Altera (VHDL)
-- 

LIBRARY ieee;                                               
USE ieee.std_logic_1164.all;                                

ENTITY fso_satcom_top_vhd_tst IS
END fso_satcom_top_vhd_tst;
ARCHITECTURE fso_satcom_top_arch OF fso_satcom_top_vhd_tst IS
    -- Component declaration for DUT
    component fso_satcom_top is
        generic (
            DATA_WIDTH     : integer := 32;
            FIFO_DEPTH     : integer := 512;
            FRAME_SIZE     : integer := 1024;
            LASER_FREQ_KHZ : integer := 1000;
            SYSTEM_CLK_MHZ : integer := 50
        );
        port (
            MAX10_CLK1_50  : in  std_logic;
            KEY            : in  std_logic_vector(1 downto 0);
            SW             : in  std_logic_vector(9 downto 0);
            LEDR           : out std_logic_vector(9 downto 0);
            HEX0           : out std_logic_vector(6 downto 0);
            HEX1           : out std_logic_vector(6 downto 0);
            HEX2           : out std_logic_vector(6 downto 0);
            HEX3           : out std_logic_vector(6 downto 0);
            HEX4           : out std_logic_vector(6 downto 0);
            HEX5           : out std_logic_vector(6 downto 0);
            GPIO           : inout std_logic_vector(35 downto 0)
        );
    end component;

    -- Testbench signals
    signal clk             : std_logic := '0';
    signal key            : std_logic_vector(1 downto 0) := "11";
    signal sw             : std_logic_vector(9 downto 0) := (others => '0');
    signal ledr           : std_logic_vector(9 downto 0);
    signal hex0, hex1, hex2, hex3, hex4, hex5 : std_logic_vector(6 downto 0);
    signal gpio           : std_logic_vector(35 downto 0) := (others => 'Z');
    signal optical_rx_data : std_logic := '0';

    -- Constants
    constant CLK_PERIOD    : time := 20 ns;  -- 50 MHz clock
    constant FRAME_SIZE    : integer := 1024;
    constant DATA_WIDTH    : integer := 32;
    constant PARITY_BITS   : integer := 8;

    -- Simulation control
    signal sim_done        : boolean := false;

begin
    -- Instantiate DUT
    uut: fso_satcom_top
    generic map (
        DATA_WIDTH     => DATA_WIDTH,
        FIFO_DEPTH     => 512,
        FRAME_SIZE     => FRAME_SIZE,
        LASER_FREQ_KHZ => 1000,
        SYSTEM_CLK_MHZ => 50
    )
    port map (
        MAX10_CLK1_50  => clk,
        KEY            => key,
        SW             => sw,
        LEDR           => ledr,
        HEX0           => hex0,
        HEX1           => hex1,
        HEX2           => hex2,
        HEX3           => hex3,
        HEX4           => hex4,
        HEX5           => hex5,
        GPIO           => gpio
    );

    -- Clock generation
    clk_process: process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Stimulus process
    stimulus: process
        procedure send_serial_data(data : std_logic_vector(39 downto 0)) is
        begin
            for i in 0 to 39 loop
                optical_rx_data <= data(i);
                wait for CLK_PERIOD * 40;  -- Simulate 1 MHz serialization (clk_1mhz)
            end loop;
            optical_rx_data <= '0';
        end procedure;

    begin
        -- Initialize inputs
        sw <= (others => '0');
        key <= "11";  -- Buttons not pressed (active-low)
        gpio(1) <= optical_rx_data;

        -- Reset sequence
        sw(9) <= '0';  -- Assert reset
        wait for CLK_PERIOD * 10;
        sw(9) <= '1';  -- Deassert reset
        wait for CLK_PERIOD * 100;

        -- Enable system (KEY[1] for system_enable)
        key <= "01";  -- Press KEY[1]
        wait for CLK_PERIOD * 1000000;  -- Wait for debouncer (1 ms)
        key <= "11";
        wait for CLK_PERIOD * 100;

        -- Enable tracking lock (KEY[0] for feedback_lock)
        key <= "10";  -- Press KEY[0]
        wait for CLK_PERIOD * 1000000;
        key <= "11";
        wait for CLK_PERIOD * 100;

        -- Set laser power (SW[8:7])
        sw(8) <= '1';
        sw(7 downto 0) <= x"FF";
        wait for CLK_PERIOD * 100;

        -- Enable data transmission (SW[3] for tx_data_valid)
        sw(3) <= '1';
        wait for CLK_PERIOD * 1000;

        -- Test display modes
        -- Display mode 001: link_quality
        sw(2 downto 0) <= "001";
        wait for CLK_PERIOD * 1000;

        -- Display mode 010: bit_error_rate
        sw(2 downto 0) <= "010";
        wait for CLK_PERIOD * 1000;

        -- Display mode 011: rx_data_out
        sw(2 downto 0) <= "011";
        wait for CLK_PERIOD * 1000;

        -- Display mode 100: rx_error_corrected
        sw(2 downto 0) <= "100";
        wait for CLK_PERIOD * 1000;

        -- Simulate optical_rx_data (40-bit frame with no errors)
        send_serial_data(x"1234567890");  -- Valid 40-bit data
        wait for CLK_PERIOD * 1000;

        -- Simulate optical_rx_data with errors (corrupt parity)
        send_serial_data(x"12345678FF");  -- Corrupted parity
        wait for CLK_PERIOD * 1000;

        -- Disable data transmission
        sw(3) <= '0';
        wait for CLK_PERIOD * 1000;

        -- End simulation
        sim_done <= true;
        wait;
    end process;

    -- Monitor outputs
    monitor: process
        variable hex0_expected : std_logic_vector(6 downto 0);
    begin
        wait for CLK_PERIOD * 100;
        while not sim_done loop
            if ledr /= "0000000000" then
                report "LEDR updated: " & to_string(ledr);
            end if;
            if hex0 /= "0000000" or hex1 /= "0000000" or hex2 /= "0000000" or
               hex3 /= "0000000" or hex4 /= "0000000" or hex5 /= "0000000" then
                report "HEX displays updated: " &
                       "HEX0=" & to_string(hex0) & ", " &
                       "HEX1=" & to_string(hex1) & ", " &
                       "HEX2=" & to_string(hex2) & ", " &
                       "HEX3=" & to_string(hex3) & ", " &
                       "HEX4=" & to_string(hex4) & ", " &
                       "HEX5=" & to_string(hex5);
            end if;
            if gpio(0) /= '0' then
                report "Optical TX data: " & to_string(gpio(0));
            end if;
            if sw(2 downto 0) = "100" then
                -- Check HEX0 for rx_error_corrected (0 or 1)
                hex0_expected := "0111111" when ledr(0) = '0' else "0000110";
                if hex0 /= hex0_expected then
                    report "HEX0 mismatch for display_mode 100: expected " & to_string(hex0_expected) &
                           ", got " & to_string(hex0) severity warning;
                end if;
            end if;
            wait for CLK_PERIOD * 100;
        end loop;
    end process;

end behavior;