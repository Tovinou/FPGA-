-- Company: AGSTU
-- Engineer: Komlan Tovinou
--
-- Create Date: 2024 03 06
-- Design Name: vga_sync
-- Target Devices: ALTERA 
-- Tool versions: Quartus 18.1 and ModelSim 
-- Testbench file: vga_sync
-- Do file: do vga_sync_run_msim_rtl_vhdl.do
-- Description: VGA-prototyp som styrs av några test knappar och där resultatet visas på en VGA-skärm.
-- 
--
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.all;
USE ieee.numeric_std.all;  

entity VGA_Sync is 
   port
      (
      clk_25      : in std_logic;
      reset_n     : in std_logic;
      KEY         : in std_logic_vector(2 downto 0);
      data        : in std_logic_vector(7 downto 0);-- ansluta till q_ab
      VGA_VS      : out std_logic;
      VGA_HS      : out std_logic;
      VGA_R       : out std_logic_vector(3 downto 0);
      VGA_G       : out std_logic_vector(3 downto 0);
      VGA_B       : out std_logic_vector(3 downto 0);
		vga_clk     : buffer std_logic:='0'; 
		VGA_BLANK_N : out std_logic;                    -- horizontal blankning signal
	   VGA_SYNC_N  : out std_logic;                    -- vertical blankning signal
		adress      : out std_logic_vector(16 downto 0) := (others => '0')  
      );
end entity;

architecture rtl of VGA_Sync is 

   ---------- could use a record for x/y counters ---------- 
	
   type HV_type is -- Horizontal/Vertical type
      record
         H : integer range 0 to 1023; -- Horizontal (x) signal
         V : integer range 0 to 525;  -- Vertical (y) signal
      end record;
   signal counter : HV_type;
   ---------- Might be overkill to use a record ----------
	
   signal x_counter              : unsigned(9 downto 0);
   signal y_counter              : unsigned(9 downto 0);
   --signal reset_n_t1, reset_n_t2 : std_logic;                    -- synchronized reset
  -- signal key_t1, key_t2         : std_logic_vector(2 downto 0); -- synchronized key

begin

------------------ Clock process ------------------
   clock_process: process(clk_25, reset_n)
   begin
      if reset_n = '0' then
         -- If reset is asserted, set VGA_CLK to '0'.
         VGA_CLK <= '0';
      elsif rising_edge(clk_25) then
         -- Toggle VGA_CLK on rising edge of clk_25
         VGA_CLK <= not VGA_CLK;
      end if;
   end process;
------------------ Clock process ------------------

------------------ Metastability process ------------------
   ---- Reset synchronization process----
  -- process(clk_25, reset_n)
  -- begin
     -- if reset_n = '0' then
        -- reset_n_t1 <= '0';
        -- reset_n_t2 <= '0';
     -- elsif rising_edge(clk_25) then
        -- reset_n_t1 <= '1';
        -- reset_n_t2 <= reset_n_t1;
    --  end if;
  -- end process;
   
   ---- Key synchronization process for metastability-----
 --  process(clk_25, reset_n_t2)
  -- begin
     -- if reset_n_t2 = '0' then
        -- key_t1 <= (others=>'0'); -- Initial assignment
        -- key_t2 <= (others=>'0');
     -- elsif rising_edge(clk_25) then
       --  key_t1 <= Key;
       --  key_t2 <= key_t1;
     -- end if;
  -- end process;    
------------------ Metastability process ------------------

------------------ Counters process ------------------
   process(clk_25, reset_n)
   begin
      if reset_n   = '0' then
         -- clear counter signals
         x_counter <= (others => '0');
         y_counter <= (others => '0');
      elsif rising_edge(clk_25) then
         -- counters
			
         -- increment x_counter (counter.H) every clock pulse
         if x_counter = 799 then
            x_counter <= (others => '0');
         else
            x_counter <= x_counter + 1; -- increment x_counter
         end if;
        
            -- increment y_counter (counter.V) when x_counter is 707
         if x_counter = 707 then
            if y_counter = 524 then 
               y_counter <= (others => '0');
            else
                y_counter <= y_counter + 1; -- increment y_counter
            end if;
         end if;
      end if;
   end process;
    ------------------ Counters process ------------------

------------------ Concurrent asynchronous statements ------------------

   ----------Sync pulses generation---------
   VGA_HS <= '0' when x_counter >= 639 and x_counter <= 755 else '1';
   VGA_VS <= '0' when y_counter  = 480                      else '1'; 
	    
   VGA_BLANK_N <= '0' when (x_counter >= 640) and (x_counter <= 799) else '1'; 
   VGA_SYNC_N  <= '0' when (y_counter >= 480) and (y_counter <= 524) else '1';   
   -- Sync pulses generation
  
    
   -- RGB signals for validation
   VGA_R <= (others => '1') when (x_counter <= 360 and y_counter <= 320) and KEY(0) = '1' else (others => '0');
   VGA_G <= (others => '1') when (x_counter <= 410 and y_counter >= 280 and y_counter <= 480) and KEY(1) = '1' else (others => '0');
   VGA_B <= (others => '1') when (x_counter >= 300 and x_counter <= 640 and y_counter >= 240 and y_counter <= 480) and KEY(2) = '1' else (others => '0');
	
------------------ Concurrent statements ------------------

   -- Red   x from 0      to 360,    y from 0    to 320
   -- Green x from 0      to 410,    y from 280  to 480
   -- Blue  x from 300    to 640,    y from 240  to 480
	

end architecture;