-- =============================================================================
-- pos_latch.vhd
-- Position Data Latch
--
-- Captures the parallel position word from ssi_master whenever 'valid' is
-- asserted (one system-clock pulse at the end of each SSI frame).
--
-- The registered output 'pos_out' is stable between frames and can be read
-- at any time by downstream logic (display drivers, LED assignments, etc.).
--
-- Generic DATA_BITS sets the data width (default 25 for a 25-bit encoder).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity pos_latch is
    generic (
        DATA_BITS : positive := 25
    );
    port (
        clk     : in  std_logic;
        rst_n   : in  std_logic;
        valid   : in  std_logic;                              -- Capture enable
        data_in : in  std_logic_vector(DATA_BITS - 1 downto 0);
        pos_out : out std_logic_vector(DATA_BITS - 1 downto 0)
    );
end entity pos_latch;

architecture rtl of pos_latch is
begin

    p_latch : process (clk, rst_n)
    begin
        if rst_n = '0' then
            pos_out <= (others => '0');
        elsif rising_edge(clk) then
            if valid = '1' then
                pos_out <= data_in;
            end if;
        end if;
    end process p_latch;

end architecture rtl;
