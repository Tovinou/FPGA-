LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;
USE ieee.std_logic_unsigned.all;

ENTITY spi_master IS
   GENERIC(
      d_width : INTEGER := 16);                              --data bus width
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
END spi_master;

ARCHITECTURE rtl OF spi_master IS
   TYPE t_state IS (idle, clock_low, clock_execute, last_s_bit, output); --state machine data type
   SIGNAL state       : t_state := idle ;                                --current state
   signal shift_mosi  : std_logic_vector(d_width-1 DOWNTO 0);
   SIGNAL shift_miso  : std_logic_vector(d_width-1 DOWNTO 0);                              
   SIGNAL count       : INTEGER range 0 to d_width;                      --counter to trigger sclk from system clock
   SIGNAL clk_toggles : STD_LOGIC:= '1';                                       --count spi clock toggles
   SIGNAL scaler_cnt  : unsigned (7 downto 0);
   SIGNAL start_s     : std_logic;
   SIGNAL clk_en      : std_logic;
   SIGNAL start_syn   : std_logic;
   SIGNAL sclk_s      : std_logic:= '0';
   SIGNAL msb_1       : std_logic:= '1';
   
BEGIN

   busy <= '0'    when state = idle OR start_syn = '0' else '1'; 
   sclk <= sclk_s ;                  
------------------------------------------------------------
   PROCESS(clock, reset_n) is
   BEGIN
      if reset_n = '0' then
         clk_en    <= '0';    
         scaler_cnt     <= (others => '0');
      ELSIF(clock'EVENT AND clock = '1') THEN
         clk_en  <= '0'; 
         if scaler_cnt   = 0 then
            clk_en  <= '1'; -- Enable clock for one cycle
            scaler_cnt    <= unsigned(scaler);-- Reload the counter
         else
			   clk_en <= '0'; -- Keep clock disabled
            scaler_cnt    <= scaler_cnt - 1; -- Decrement the counter
         end if;   
      end if;
   end process;       
-------------------------------------------------------------------
   PROCESS(clock, reset_n)
   BEGIN
      IF(reset_n  = '0') THEN                  --reset system
         state      <= idle;                  --set idle signal
         shift_mosi <= (others => '0');
         shift_miso <= (others => '0');
         start_s    <= '0';
         start_syn  <= '0';
         count      <=  0;   
         ----- outouts
         sclk_s     <= '0';
         mosi       <= '0';                   --set master out to high impedance
         cs_n       <= '1';                   --deassert all slave select lines
         rx_data    <= (others => '0');       --clear receive data port
         div        <= '0';        
      ELSIF(clock'EVENT AND clock = '1') THEN
         start_s    <= start;                 --go to ready state when reset is exited
         if start_s  = '0'and start = '1' then
         start_syn  <= '1';
      end if; 
-----------------------------------------------------------
         if clk_en = '1' then
            case state is                           --idle state
               when idle =>
                  rx_data      <= (others => '0');
                  div          <= '0';
                  mosi         <= '0';
                  if start_syn = '1' then
                     cs_n      <= '0';
                     count     <= d_width-1;
                     shift_mosi<= tx_data;
							sclk_s     <= cpol;            --set spi clock polarity
                     start_syn <= '0';
							-- clk_en <= '1';  -- Set clock enable signal to '1' in reset state
                     state     <= clock_low;
                  end if;
------------------------------------------------------------      
               when clock_low =>                                             --clock low state
                  sclk_s        <= '0'; 
                  MSB_1         <= shift_mosi(d_width-1);         
                  if MSB_1      =  '1' then 
                     mosi       <= shift_mosi (d_width-1);                   --MSB
                     shift_mosi <= shift_mosi (d_width - 2 DOWNTO 0) & '0';
                     shift_miso <= shift_miso (d_width - 2 DOWNTO 0) & miso; --read input data                    
                     state            <= clock_execute;
                  end if;
----------------------------------------------------------------------
               when clock_execute  =>                                           --exection state
                  sclk_s <= '1';
                  if count  = 0 then
                     state <= last_s_bit;
                  else
                     count <= count-1;
                     state <= clock_low;
                  end if;
---------------------------------------------------------------------------
               when last_s_bit =>                                         --last significant bits state
                  shift_miso <= shift_miso(d_width - 2 DOWNTO 0) & miso;
                  state      <= output;
-------------------------------------------------------------------------------------
               when output =>
                  rx_data  <= shift_miso;
                  div      <= '1';
                  mosi    <= '0';                                        --LSB
                  state    <= idle;
-----------------------------------------------------------------------------------------
               when others => 
                  state <= idle;
--------------------------------------------------------------------------------------         
            end case;
         end if;
      end if;
   end process;

end architecture rtl;