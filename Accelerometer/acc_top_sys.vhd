-- System Architecture Description: acc_top_sys
-- Author: Komlan Tovinou
-- Date: 2024-03-06
-- Company: AGSTU
-- 
-- This VHDL design describes a system that interfaces an ADXL345 accelerometer with a VGA display
-- and outputs acceleration data on 7-segment displays. The design is targeted for an ALTERA FPGA
-- and developed using Quartus 18.1 and ModelSim.
---------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;  
USE ieee.std_logic_arith.all;

ENTITY acc_top_sys IS
   GENERIC
   (       
      d_width : INTEGER := 16                              --data bus width
   );
   PORT
      (
      clock_50       : IN     STD_LOGIC;                   --system clock
      reset_n        : IN     STD_LOGIC;                   --active low asynchronous reset
      miso           : IN     STD_LOGIC;                   --master in, slave out     
      sclk           : OUT    STD_LOGIC;                   --SPI serial clock
      ss_n           : OUT    STD_LOGIC;                   --SPI bus: slave select
      mosi           : OUT    STD_LOGIC;                   --SPI bus: master out, slave in                  
      -----vga ports--------------------------------------------     
      vga_vs         : OUT    STD_LOGIC;
      vga_hs         : OUT    STD_LOGIC;
      vga_r          : OUT    STD_LOGIC_VECTOR(3 downto 0);
      vga_g          : OUT    STD_LOGIC_VECTOR(3 downto 0);
      vga_b          : OUT    STD_LOGIC_VECTOR(3 downto 0);
      -- 7-segment display outputs for each axis
      hex0           : OUT    STD_LOGIC_VECTOR (6 downto 0);  -- 7-segment display for X-axis value
      hex1           : OUT    STD_LOGIC_VECTOR (6 downto 0);  -- 7-segment display for Y-axis value
      hex2           : OUT    STD_LOGIC_VECTOR (6 downto 0)   -- 7-segment display for Z-axis value
      );  
END acc_top_sys;

ARCHITECTURE behavior OF acc_top_sys IS
   signal s_scaler       : STD_LOGIC_VECTOR(7 DOWNTO 0):= (OTHERS => '0');   
   signal s_dv           : STD_LOGIC;     -- data valid
   signal s_busy         : STD_LOGIC;     -- busy signal from spi
   signal acc_ss_n       : STD_LOGIC; --SPI bus: slave select
   signal spi_mosi       : STD_LOGIC;
   signal i_spi_rx_data  : STD_LOGIC_VECTOR(d_width-1 DOWNTO 0):= (OTHERS => '0'); --received data from SPI component
   signal o_spi_tx_data  : STD_LOGIC_VECTOR(d_width-1 DOWNTO 0):= (OTHERS => '0'); --transmit data for SPI component
   signal o_spi_start    : STD_LOGIC:= '1';                   --connect to spi clock phase  
   signal o_acc_x        : STD_LOGIC_VECTOR(15 DOWNTO 0);--x-axis acceleration data
   signal o_acc_y        : STD_LOGIC_VECTOR(15 DOWNTO 0);--y-axis acceleration data
   signal o_acc_z        : STD_LOGIC_VECTOR(15 DOWNTO 0); --z-axis acceleration data
   signal adress_vga_w   : STD_LOGIC_VECTOR(16 downto 0):= (others => '0'); -- För att adressera 76800 pixlar
   signal data_vga_w     : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
   signal write_VGA      : STD_LOGIC:= '0';
   signal reset_n_t2     : STD_LOGIC := '0';    
   signal data_xyz       : STD_LOGIC_VECTOR(2 downto 0);
   --signal sclk_t2         : std_logic:= '1'; --hold the value for the sclk output from the accelerometer
 
------ Component Declarations ------

component accelerometer_adxl345 is
   GENERIC
   (
      d_width         : INTEGER := 16                  --data bus width
      
   );
   PORT
      (
      clk            : IN     STD_LOGIC;                    --system clock
      reset_n        : IN     STD_LOGIC;                    --active low asynchronous reset
      spi_busy       : IN     STD_LOGIC;                    --busy signal from SPI component
      dv             : IN     STD_LOGIC;                    --data valid
      spi_tx_data    : OUT    STD_LOGIC_VECTOR(d_width-1 DOWNTO 0); -- Received data from SPI component
      spi_rx_data    : IN     STD_LOGIC_VECTOR(d_width-1 DOWNTO 0); -- Transmit data for SPI component
      --sclk         : OUT    STD_LOGIC:= '1';              --SPI bus: serial clock
      ss_n           : OUT    STD_LOGIC                    ;--SPI bus: slave select
      acc_mosi       : OUT    STD_LOGIC:= '1';              --SPI bus: master out, slave in            
      acc_start      : OUT    STD_LOGIC:= '0';          -- Trigger signal from the accelerometer
      acceleration_x : OUT    STD_LOGIC_VECTOR(15 DOWNTO 0);--x-axis acceleration data
      acceleration_y : OUT    STD_LOGIC_VECTOR(15 DOWNTO 0);--y-axis acceleration data
      acceleration_z : OUT    STD_LOGIC_VECTOR(15 DOWNTO 0) --z-axis acceleration data
      
      );  
END component accelerometer_adxl345;

component metastability is
   port
      (
      clk        : in     std_logic;
      reset_n    : in     std_logic;
      --key      : in     std_logic_vector(2 downto 0);
      --sclk     : in     std_logic;
      reset_n_t2 : out    std_logic
      --sclk_t2  : out    std_logic;
      --key_t2   : out    std_logic_vector(2 downto 0)
      );
end component;

component spi_master is
   GENERIC
   (       
      d_width : INTEGER := 16                                --data bus width
   );
   PORT
      (
      clock   : IN     STD_LOGIC;                            --system clock
      reset_n : IN     STD_LOGIC;                            --asynchronous reset
      scaler  : IN     STD_LOGIC_vector(7 downto 0);                             
      cpol    : IN     STD_LOGIC;                            --spi clock polarity
      start   : IN     STD_LOGIC;                            --spi clock phase
      div     : OUT    std_logic;    
      tx_data : IN     STD_LOGIC_VECTOR(d_width-1 DOWNTO 0); --data to transmit
      miso    : IN     STD_LOGIC;                            --master in, slave out
      sclk    : OUT    STD_LOGIC;                            --spi clock
      cs_n    : OUT    STD_LOGIC;                            --slave select
      mosi    : OUT    STD_LOGIC;                            --master out, slave in
      busy    : OUT    STD_LOGIC;                            --busy / data ready signal
      rx_data : OUT    STD_LOGIC_VECTOR(d_width-1 DOWNTO 0)  --data received
      );
END component spi_master;

component VGA_komponent is
   port
      (
      CLOCK_50          : in std_logic;
      reset_n           : in std_logic;
      KEY               : in std_logic_vector(2 downto 0);
       ---hall till VGA enheten---
      VGA_VS            : out std_logic;
      VGA_HS            : out std_logic;
      VGA_R             : out std_logic_vector(3 downto 0);
      VGA_G             : out std_logic_vector(3 downto 0);
      VGA_B             : out std_logic_vector(3 downto 0);
      adress_vga_w      : in  std_logic_vector(16 downto 0):= (others => '0'); -- För att adressera 76800 pixlar
      data_vga_w        : in  std_logic_vector(7 downto 0) := (others => '0');
      write_VGA         : in  std_logic:= '0'      
      );
   end component;
   
component data_interface is
   port  
      (
      reset_n     : IN  STD_LOGIC;
      clock_50    : IN  STD_LOGIC;
      acc_x       : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
      acc_y       : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
      acc_z       : IN  STD_LOGIC_VECTOR(15 DOWNTO 0);
      data_x_y_z  : OUT STD_LOGIC_VECTOR(2 DOWNTO 0)
      );
   end component;
component Accel_Display is
   port
      (
      clk       : in  STD_LOGIC;                      -- System clock
      reset_n   : in  STD_LOGIC;                      -- Active low asynchronous reset
      i_accel_x : in STD_LOGIC_VECTOR (15 downto 0);  -- 16-bit signed X-axis acceleration
      i_accel_y : in STD_LOGIC_VECTOR (15 downto 0);  -- 16-bit signed Y-axis acceleration
      i_accel_z : in STD_LOGIC_VECTOR (15 downto 0);  -- 16-bit signed Z-axis acceleration        
      -- 7-segment display outputs for each axis
      o_hex0    : out STD_LOGIC_VECTOR (6 downto 0);  -- 7-segment display for X-axis value
      o_hex1    : out STD_LOGIC_VECTOR (6 downto 0);  -- 7-segment display for Y-axis value
      o_hex2    : out STD_LOGIC_VECTOR (6 downto 0)   -- 7-segment display for Z-axis valu
      );
   end component;

begin

-- Instantiation of metastability  component
   b2v_inst_metastability : metastability
      port map(
         clk        => clock_50,
         reset_n    => reset_n,
         --key        => key,
         --sclk       => s_sclk,
         reset_n_t2 => reset_n_t2
         --sclk_t2    => sclk_t2
         --key_t2     => key_t2
      ); 
      
---------Instantiation of components-------------------   
   -- Instantiation of accelerometer_adxl345 component
   b2v_inst_accelerometer_adxl345 : accelerometer_adxl345
      generic map (
         d_width         => 16                
         
      )
      port map(
         clk            => clock_50,  
         reset_n        => reset_n_t2,
         spi_busy       => s_busy,
         dv             => s_dv,
         spi_tx_data    => o_spi_tx_data,
         spi_rx_data    => i_spi_rx_data,
         --sclk         => sclk_t2,
         ss_n           => acc_ss_n,
         acc_mosi       => spi_mosi,       
         acc_start      => o_spi_start,
         acceleration_x => o_acc_x,
         acceleration_y => o_acc_y,
         acceleration_z => o_acc_z
      ); 
 
   -- Instantiation of spi_master component
   b2v_inst_spi_master : spi_master
      generic map (
         d_width => 16
      )
      port map(
         clock   => clock_50,
         reset_n => reset_n_t2,
         scaler  => s_scaler,   
         cpol    => '1',
         start   => o_spi_start,
         div     => s_dv,
         tx_data => o_spi_tx_data,
         miso    => miso,
         sclk    => sclk,
         cs_n    => ss_n,
         mosi    => mosi,
         busy    => s_busy,
         rx_data => i_spi_rx_data
      );
  
   -- Instantiation of VGA_komponent component
   b2v_inst_vga_komponent : vga_komponent
      port map(
         clock_50     => clock_50,
         reset_n      => reset_n_t2,
         KEY          => data_xyz,
         VGA_VS       => vga_vs,
         VGA_HS       => vga_hs,
         VGA_R        => vga_r,
         VGA_G        => vga_g,
         VGA_B        => vga_b,
         adress_vga_w => adress_vga_w,   
         data_vga_w   => data_vga_w,   
         write_VGA    => write_VGA           
      );
   
   -- Instantiation of data_interface component
   b2v_inst_data_interface : data_interface
      port map(
         clock_50   => clock_50,
         reset_n    => reset_n_t2,
         acc_x      => o_acc_x,
         acc_y      => o_acc_y,
         acc_z      => o_acc_z,
         data_x_y_z => data_xyz           
      );
   
   -- Instantiation of Accel_Display component
   b2v_inst_Accel_Display : Accel_Display
      port map(
		   clk       => clock_50,
			reset_n   => reset_n_t2,
         i_accel_x => o_acc_x,
         i_accel_y => o_acc_y,
         i_accel_z => o_acc_z,   
         o_hex0    => hex0,
         o_hex1    => hex1,
         o_hex2    => hex2
      );
     
end architecture behavior;
