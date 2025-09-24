LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY accelerometer_adxl345 IS
   GENERIC(
      d_width         : INTEGER := 16                  -- Data bus width
   );
   PORT
   (
      clk            : IN     STD_LOGIC;                   -- System clock
      reset_n        : IN     STD_LOGIC;                   -- Active low asynchronous reset
      spi_busy       : IN     STD_LOGIC;                   -- Busy signal from SPI component
      dv             : IN     STD_LOGIC;                   -- Data valid
      spi_tx_data    : OUT    STD_LOGIC_VECTOR(d_width-1 DOWNTO 0); -- Received data from SPI component
      spi_rx_data    : IN     STD_LOGIC_VECTOR(d_width-1 DOWNTO 0); -- Transmit data for SPI component
      --sclk         : OUT    STD_LOGIC;                   -- SPI bus: serial clock
      ss_n           : OUT    STD_LOGIC;                   -- SPI bus: slave select
      acc_mosi       : OUT    STD_LOGIC;                   -- SPI bus: master out, slave in
      acceleration_x : OUT    STD_LOGIC_VECTOR(15 DOWNTO 0);-- X-axis acceleration data
      acceleration_y : OUT    STD_LOGIC_VECTOR(15 DOWNTO 0);-- Y-axis acceleration data
      acceleration_z : OUT    STD_LOGIC_VECTOR(15 DOWNTO 0); -- Z-axis acceleration data     
      acc_start      : OUT    STD_LOGIC := '0'             -- Trigger signal from the accelerometer    
   );   
END accelerometer_adxl345;

ARCHITECTURE behavior OF accelerometer_adxl345 IS
   TYPE machine IS (start, pause, configure, read_data, output_result);-- Needed states
   SIGNAL state              : machine := start;                       -- State machine
   SIGNAL count              : INTEGER;           -- Universal counter 
   SIGNAL param              : INTEGER RANGE 0 TO 4;                   -- Parameter being configured
   SIGNAL param_addr         : STD_LOGIC_VECTOR(7 DOWNTO 0) := (others => '0'); -- Register address of configuration parameter
   SIGNAL param_data         : STD_LOGIC_VECTOR(7 DOWNTO 0) := (others => '0'); -- Value of configuration parameter
   SIGNAL spi_busy_prev      : STD_LOGIC;                              -- Previous value of the SPI component's busy signal
   SIGNAL spi_ena            : STD_LOGIC := '0';                       -- Enable for SPI component
   SIGNAL spi_cont           : STD_LOGIC := '0';                       -- Continuous mode signal for SPI component   
   SIGNAL acceleration_x_int : STD_LOGIC_VECTOR(15 DOWNTO 0) := (others => '0'); -- Internal x-axis acceleration data buffer
   SIGNAL acceleration_y_int : STD_LOGIC_VECTOR(15 DOWNTO 0) := (others => '0'); -- Internal y-axis acceleration data buffer
   SIGNAL acceleration_z_int : STD_LOGIC_VECTOR(15 DOWNTO 0) := (others => '0'); -- Internal z-axis acceleration data buffer
   SIGNAL spi_rx_data_int    : STD_LOGIC_VECTOR(d_width-1 DOWNTO 0) := (others => '0'); -- for capturing received SPI data.
   
BEGIN

   acc_mosi <= spi_tx_data(d_width-1); -- Connect MOSI to the most significant bit of spi_tx_data  
     
   PROCESS(clk, reset_n)
   BEGIN
      IF reset_n = '0' THEN         -- Reset activated
         spi_busy_prev  <= '0';             -- Clear previous value of SPI component's busy signal
         spi_ena        <= '0';             -- Clear SPI component enable
         spi_cont       <= '0';             -- Clear SPI component continuous mode signal
         ss_n           <= '1';             -- Deassert all slave select lines 
         spi_tx_data    <= (OTHERS => '0'); -- Clear SPI component transmit data
         acceleration_x <= (OTHERS => '0'); -- Clear x-axis acceleration data
         acceleration_y <= (OTHERS => '0'); -- Clear y-axis acceleration data
         acceleration_z <= (OTHERS => '0'); -- Clear z-axis acceleration data
         state <= start;                    -- Restart state machine
      ELSIF rising_edge(clk) THEN           -- Rising edge of system clock
         CASE state IS                      -- State machine
------------------------------------------------------------------------------
            -- Entry state
            WHEN start =>
                  count <= 0;                  -- Clear universal counter
                  param <= 0;                  -- Clear parameter indicator
                  state <= configure;          -- Proceed to configure state
               
----------------------------------------------------------------------------------                    
            -- Pauses 200ns between SPI transactions and selects SPI transaction
            WHEN pause =>
               IF spi_busy = '0' THEN       -- SPI component not busy
                  count <= count + 1;       -- Increment counter
                  IF count = 2 THEN          -- Check if the pause duration has elapsed
                     count <= 0;            -- Clear counter
                     CASE param IS           -- Select SPI transaction
                        WHEN 0 =>           -- SPI transaction to set range
                           param <= param + 1;   -- Increment parameter for next transaction
                           param_addr <= "00110010"; -- Register address for DATAX0 (0x32)
                           param_data <= "10000000"; -- Data to set specified range
                           state <= configure;           -- Proceed to SPI transaction to configure
                        WHEN 1 =>           -- SPI transaction to set data rate
                           param <= param + 1;   -- Increment parameter for next transaction
                           param_addr <= "00110011"; -- Register address for DATAX1 (0x33)
                           param_data <= "10010000";
                           state <= configure;           -- Proceed to SPI transaction to configure
                        WHEN 2 =>           -- SPI transaction to enable measurement
                           param <= param + 1;   -- Increment parameter for next transaction
                           param_addr <= "00110100"; -- Register address for DATAY0 (0x34)
                           param_data <= "10110000"; -- Data to enable measurement
                           state <= configure;           -- Proceed to SPI transaction to configure
                        WHEN 3 =>           -- SPI transaction to enable measurement
                           param <= param + 1;   -- Increment parameter for next transaction
                           param_addr <= "00110101"; -- Register address for DATAY1 (0x35)
                           param_data <= "10000111"; -- Data to enable measurement
                           state <= configure;           -- Proceed to SPI transaction to configure
                        WHEN OTHERS => NULL;
                     END CASE;
                  END IF;
               END IF;
----------------------------------------------------------------- ---------------  
            -- Performs SPI transactions that write to configuration registers  
            WHEN configure =>
               spi_busy_prev <= spi_busy;  -- Capture the value of the previous spi busy signal
               IF spi_busy_prev = '1' AND spi_busy = '0' THEN -- SPI busy just went low
                  count <= count + 1;      -- Counts times busy goes from high to low during transaction
               END IF;
               CASE count IS                -- Number of times busy has gone from high to low
                  WHEN 0 =>                 -- No busy deassertions
                     IF spi_busy = '0' THEN -- Transaction not started
                        spi_cont <= '1';    -- Set to continuous mode
                        spi_ena <= '1';     -- Enable SPI transaction
                        spi_tx_data <= param_addr & param_data; -- First information to send
                     ELSE                   -- Transaction has started
                        spi_tx_data <= param_addr & param_data; -- Second information to send (first has been latched in)
                     END IF;
                  WHEN 1 =>                 -- First busy deassertion
                     spi_cont <= '0';       -- Clear continuous mode to end transaction
                     spi_ena <= '0';        -- Clear SPI transaction enable
                     count <= 0;            -- Clear universal counter
                     state <= pause;        -- Return to pause state
                  WHEN OTHERS => NULL;
               END CASE;
---------------------------------------------------------------------------------   
            -- Performs SPI transactions that read acceleration data registers  
            WHEN read_data =>
               spi_busy_prev <= spi_busy;  -- Capture the value of the previous spi busy signal
               IF spi_busy_prev = '1' AND spi_busy = '0' THEN -- SPI busy just went low
                  count <= count + 1;      -- Counts the times busy goes from high to low during transaction
               END IF;          
               CASE count IS                -- Number of times busy has gone from high to low
                  WHEN 0 =>                 -- No busy deassertions
                     IF spi_busy = '0' THEN -- Transaction not started
                        spi_cont <= '1';    -- Set to continuous mode
                        spi_ena <= '1';     -- Enable SPI transaction
                        spi_tx_data <= "11110010" & param_data; -- First information to send
                     ELSE                   -- Transaction has started
                        spi_tx_data <= "00000000" & param_data; -- Second information to send (first has been latched in)              
                     END IF;
                  
                  WHEN 2 =>                  -- 2nd busy deassertion
                     acceleration_x_int <= spi_rx_data;  -- Latch in first and second received acceleration data
                  WHEN 4 =>                  -- 4th busy deassertion
                     acceleration_y_int <= spi_rx_data;  -- Latch in third and fourth received acceleration data
                  WHEN 6 =>                  -- 6th busy deassertion
                        acceleration_z_int <= spi_rx_data;  -- Latch in fifth and sixth received acceleration data              
                     spi_cont <= '0';       -- Clear continuous mode to end transaction
                     spi_ena <= '0';        -- Clear SPI transaction enable
                     count <= 0;            -- Clear universal counter
                     state <= output_result;-- Proceed to output result state
                  WHEN OTHERS => NULL;
               END CASE;
----------------------------------------------------------------------------------      
            -- Outputs acceleration data
            WHEN output_result =>
               acceleration_x <= acceleration_x_int; -- Output x-axis data
               acceleration_y <= acceleration_y_int; -- Output y-axis data
               acceleration_z <= acceleration_z_int; -- Output z-axis data
               state <= pause;                       -- Return to pause state
---------------------------------------------------------------------------------            
            -- Default to start state
            WHEN OTHERS => 
               state <= start;
----------------------------------------------------------------------------------
         END CASE;      
      END IF;
   END PROCESS;
END behavior;
