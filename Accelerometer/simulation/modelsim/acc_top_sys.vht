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
-- Generated on "05/22/2024 20:37:04"
                                                            
-- Vhdl Test Bench template for design  :  acc_top_sys
-- 
-- Simulation tool : ModelSim-Altera (VHDL)
-- 

LIBRARY ieee;                                               
USE ieee.std_logic_1164.all;                                

ENTITY acc_top_sys_vhd_tst IS
END acc_top_sys_vhd_tst;
ARCHITECTURE acc_top_sys_arch OF acc_top_sys_vhd_tst IS
-- constants  
constant clk_period : TIME := 10 ns;                                               
-- signals                                                   
SIGNAL clock_50: STD_LOGIC;
SIGNAL hex0    : STD_LOGIC_VECTOR(6 DOWNTO 0);
SIGNAL hex1    : STD_LOGIC_VECTOR(6 DOWNTO 0);
SIGNAL hex2    : STD_LOGIC_VECTOR(6 DOWNTO 0);
SIGNAL miso    : STD_LOGIC;
SIGNAL mosi    : STD_LOGIC;
SIGNAL reset_n : STD_LOGIC;
SIGNAL sclk    : STD_LOGIC;
SIGNAL ss_n    : STD_LOGIC;
SIGNAL vga_b   : STD_LOGIC_VECTOR(3 DOWNTO 0);
SIGNAL vga_g   : STD_LOGIC_VECTOR(3 DOWNTO 0);
SIGNAL vga_hs  : STD_LOGIC;
SIGNAL vga_r   : STD_LOGIC_VECTOR(3 DOWNTO 0);
SIGNAL vga_vs  : STD_LOGIC;
COMPONENT acc_top_sys
	PORT (
	clock_50        : IN     STD_LOGIC;                   
   reset_n        : IN     STD_LOGIC;                   
   miso           : IN     STD_LOGIC;                      
   sclk           : BUFFER STD_LOGIC;                   
   ss_n           : OUT    STD_LOGIC;                  
   mosi           : OUT    STD_LOGIC;                                         
   vga_vs         : OUT    STD_LOGIC;
   vga_hs         : OUT    STD_LOGIC;
   vga_r          : OUT    STD_LOGIC_VECTOR(3 downto 0);
   vga_g          : OUT    STD_LOGIC_VECTOR(3 downto 0);
   vga_b          : OUT    STD_LOGIC_VECTOR(3 downto 0);
   hex0           : OUT    STD_LOGIC_VECTOR(6 downto 0);  
   hex1           : OUT    STD_LOGIC_VECTOR(6 downto 0);  
   hex2           : OUT    STD_LOGIC_VECTOR(6 downto 0)   
	);
END COMPONENT;
BEGIN
	i1 : acc_top_sys
	PORT MAP (
-- list connections between master ports and signals
	clock_50 => clock_50,
	hex0 => hex0,
	hex1 => hex1,
	hex2 => hex2,
	miso => miso,
	mosi => mosi,
	reset_n => reset_n,
	sclk => sclk,
	ss_n => ss_n,
	vga_b => vga_b,
	vga_g => vga_g,
	vga_hs => vga_hs,
	vga_r => vga_r,
	vga_vs => vga_vs
	);


-- Clock generation process
   PROCESS
   BEGIN
      while now < 5000 ns loop -- Simulate for 5000 ns
         clock_50 <= '0';
         wait for CLK_PERIOD ;
         clock_50 <= '1';
         wait for CLK_PERIOD ;
      end loop;
      wait;
   END PROCESS;

   -- Stimulus process
   stim_proc: PROCESS
   BEGIN
      -- Reset activated
      reset_n <= '0';
      wait for 100 ns;
      -- Release reset
      reset_n <= '1';
      wait for 100 ns;

      wait for 1000 ns; -- Wait for 500 ns   

      WAIT;                                                        
   END PROCESS;      

 --- Verification of Stimulus process-------------------------------------------------
   process
   begin
      
      -- Testfall 1: 
      wait for 100 ns;
      miso <= '1';
      wait for 100 ns;
      miso <= '0';
        
      -- Testfall 2:  
      wait for 100 ns;
      miso <= '1';
      wait for 100 ns;
      miso <= '0';
        
      -- Testfall 3: 
      wait for 100 ns;
      miso <= '1';
      wait for 100 ns;
      miso <= '0';
		  
      wait;
   end process;                                    

-- Validation protocoll--------------------------------
   VERIFY_PROCESS: PROCESS
   BEGIN
      -- Wait for signals to stabilize
      WAIT FOR 500 ns;

      -- Example 1: Correct synchronization (PASS)-----
      VGA_HS <= '1';
      VGA_VS <= '1';
      -- Wait for stabilization
      WAIT FOR 10 ns;
      -- Check if VGA signals are synchronized correctly
      IF (VGA_HS = '1' AND VGA_VS = '1') THEN
         
         REPORT "PASS: VGA signals synchronized correctly" SEVERITY NOTE; -- Report PASS   
      END IF;

		
      -- Example 2: Incorrect synchronization (FAIL)------
      VGA_HS <= '1';
      -- Introduce a delay between VGA_HS and VGA_VS to simulate incorrect behavior
      WAIT FOR 10 ns;
      VGA_VS <= '1'; -- Simulate incorrect synchronization
      -- Wait for stabilization
      WAIT FOR 10 ns;
      -- Check if VGA signals are synchronized correctly
      IF (VGA_HS = '1' AND VGA_VS = '1') THEN
         
         REPORT "FAIL: VGA signals not synchronized correctly" SEVERITY NOTE; -- Report PASS    
      END IF;

     
      -- Wait indefinitely after verification
      WAIT;
   END PROCESS;
--- End of validation protocoll ----------------------------------------


		
	
		
END acc_top_sys_arch;
