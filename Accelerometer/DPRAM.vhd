-- Quartus Prime VHDL Template
-- True Dual-Port RAM with dual clock
--
-- Read-during-write on port A or B returns newly written data
-- 
-- Read-during-write on port A and B returns unknown data.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DPRAM is
   generic 
   (
      DATA_WIDTH : natural := 8;
      ADDR_WIDTH : natural := 6
   );
   port 
   (
      clk_a    : in std_logic;
      clk_b    : in std_logic;
      addr_a   : in std_logic_vector(ADDR_WIDTH - 1 downto 0); -- std_logic_vector for address A
      addr_b   : in std_logic_vector(ADDR_WIDTH - 1 downto 0); -- std_logic_vector for address B
      data_a   : in std_logic_vector(DATA_WIDTH - 1 downto 0);
      data_b   : in std_logic_vector(DATA_WIDTH - 1 downto 0);
      we_a     : in std_logic := '1';
      we_b     : in std_logic := '1';
      q_a      : out std_logic_vector(DATA_WIDTH - 1 downto 0);
      q_b      : out std_logic_vector(DATA_WIDTH - 1 downto 0)
   );
end DPRAM;

architecture rtl of DPRAM is
   subtype word_t is std_logic_vector(DATA_WIDTH - 1 downto 0);
   type memory_t is array(2**ADDR_WIDTH - 1 downto 0) of word_t;
   shared variable ram : memory_t;
begin
   -- Port A
   process(clk_a)
   begin
      if rising_edge(clk_a) then 
         if we_a = '1' then
            ram(to_integer(unsigned(addr_a))) := data_a;
         end if;
            q_a <= ram(to_integer(unsigned(addr_a)));
      end if;
   end process;

   -- Port B
   process(clk_b)
   begin
      if rising_edge(clk_b) then 
         if we_b = '1' then
            ram(to_integer(unsigned(addr_b))) := data_b;
         end if;
            q_b <= ram(to_integer(unsigned(addr_b)));
      end if;
   end process;

end rtl;
