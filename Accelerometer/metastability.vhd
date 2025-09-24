LIBRARY ieee;
USE ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity metastability is
   port
      (
      clk        : in     std_logic; -- 50 MHz clock
      reset_n    : in     std_logic;
		--key        : in     std_logic_vector(2 downto 0);
		--sclk       : in     std_logic;
      reset_n_t2 : out    std_logic
		--sclk_t2    : out    std_logic
		--key_t2     : out    std_logic_vector(2 downto 0)
      );
   end metastability;

architecture rtl of metastability is
   signal reset_n_t1 : std_logic;
	--signal sclk_t1    : std_logic;
	--signal key_t1     : std_logic_vector(2 downto 0);
	
begin

---- Reset synchronization process----
   process(clk, reset_n)
   begin
      if reset_n     = '0' then
         reset_n_t1 <= '0';
         reset_n_t2 <= '0';
      elsif rising_edge(clk) then
         reset_n_t1 <= '1';
         reset_n_t2 <= reset_n_t1;
      end if;
   end process;
	
	--sclk_process : process (clk, reset_n_t2)
	--begin
		--if reset_n_t2 = '0' then
			--sclk_t1   <= '0';
			--sclk_t2   <= '0';
		--elsif rising_edge(clk) then
			--sclk_t1   <= sclk;
			--sclk_t2   <= sclk_t1;
		--end if;
	--end process;
	
	------------------ Metastability process ------------------
   
   
   ---- Key synchronization process for metastability-----
  -- process(clk, reset_n_t2)
   --begin
      --if reset_n_t2 = '0' then
         --key_t1 <= (others=>'0'); -- Initial assignment
         --key_t2 <= (others=>'0');
      --elsif rising_edge(clk) then
         --key_t1 <= Key;
         --key_t2 <= key_t1;
      --end if;
   --end process;    
------------------ Metastability process ------------------

end architecture;