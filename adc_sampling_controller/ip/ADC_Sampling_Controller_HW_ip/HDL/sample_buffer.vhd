--------------------------------------------------------------------------------
-- sample_buffer.vhd
--
-- Dual-port sample RAM for the High-Speed ADC Sampling Controller.
--
-- Port A (write side)  : clocked by the system clock, written by the sampling
--                         controller every time a new ADC response arrives.
--                         Free-running, single-cycle write, no stalls -- this
--                         is what allows the controller to keep up with
--                         back-to-back ADC responses at the timer trigger rate.
-- Port B (read side)   : clocked by the same system clock, read by the
--                         Avalon-MM register interface so a host (Nios V,
--                         JTAG-to-Avalon master, or test bench) can pull a
--                         captured burst out of the buffer after the run
--                         completes.
--
-- DEPTH is a generic so the same component serves a "quick look" 256-sample
-- buffer or a full 1024/4096-sample burst buffer without editing source.
-- On MAX 10 this infers into the on-chip M9K memory blocks.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity sample_buffer is
   generic (
      DATA_WIDTH : integer := 12;   -- MAX10 internal ADC resolution
      DEPTH      : integer := 1024; -- number of samples held (power of 2)
      ADDR_WIDTH : integer := 10    -- log2(DEPTH)
   );
   port (
      clk         : in  std_logic;

      -- Write port (sampling controller side)
      wr_en       : in  std_logic;
      wr_addr     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
      wr_data     : in  std_logic_vector(DATA_WIDTH-1 downto 0);

      -- Read port (Avalon-MM register interface side)
      rd_addr     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
      rd_data     : out std_logic_vector(DATA_WIDTH-1 downto 0)
   );
end entity sample_buffer;

architecture rtl of sample_buffer is

   type ram_array_t is array (0 to DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
   signal ram : ram_array_t;

   signal rd_addr_reg : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');

begin

   ------------------------------------------------------------------
   -- Write port: simple synchronous write, no reset on the RAM itself
   -- (matches typical M9K inferencing -- contents are valid only after
   -- the first full write pass; the controller always writes before
   -- a region is read).
   ------------------------------------------------------------------
   write_proc : process(clk)
   begin
      if rising_edge(clk) then
         if wr_en = '1' then
            ram(to_integer(unsigned(wr_addr))) <= wr_data;
         end if;
      end if;
   end process write_proc;

   ------------------------------------------------------------------
   -- Read port: registered address -> registered data, one cycle of
   -- read latency, which is what the Avalon-MM wrapper expects.
   ------------------------------------------------------------------
   read_proc : process(clk)
   begin
      if rising_edge(clk) then
         rd_addr_reg <= rd_addr;
      end if;
   end process read_proc;

   rd_data <= ram(to_integer(unsigned(rd_addr_reg)));

end architecture rtl;
