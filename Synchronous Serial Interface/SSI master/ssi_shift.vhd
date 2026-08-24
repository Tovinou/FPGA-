-- =============================================================================
-- ssi_shift.vhd
-- SSI Shift Engine
--
-- Tracks the SSI clock phase and samples ssi_data on every rising edge of the
-- virtual SSI clock (clk_phase: 0→1 transition).  Bits arrive MSB first.
--
-- clk_phase  : driven internally; also exported to the FSM for transition logic
-- last_bit   : combinational; high when bit_cnt has reached DATA_BITS - 1
-- data_out   : latched output register; stable from the DONE pulse onward
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity ssi_shift is
    generic (
        DATA_BITS : positive := 25
    );
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;
        -- From FSM
        shifting  : in  std_logic;    -- HIGH while FSM is in SHIFTING state
        latch     : in  std_logic;    -- HIGH for one cycle when FSM enters DONE
        -- From clock divider
        clk_en    : in  std_logic;    -- Half-period tick
        -- SSI data input
        ssi_data  : in  std_logic;
        -- To FSM
        clk_phase : out std_logic;
        last_bit  : out std_logic;
        -- Captured parallel result
        data_out  : out std_logic_vector(DATA_BITS - 1 downto 0)
    );
end entity ssi_shift;

architecture rtl of ssi_shift is

    constant C_BIT_CNT_W : positive :=
        integer(ceil(log2(real(DATA_BITS + 1))));

    signal clk_phase_r : std_logic := '0';
    signal bit_cnt     : unsigned(C_BIT_CNT_W - 1 downto 0) := (others => '0');
    signal shift_reg   : std_logic_vector(DATA_BITS - 1 downto 0) := (others => '0');

begin

    -- -------------------------------------------------------------------------
    -- Phase tracker, bit counter and shift register
    -- -------------------------------------------------------------------------
    p_shift : process (clk, rst_n)
    begin
        if rst_n = '0' then
            clk_phase_r <= '0';
            bit_cnt     <= (others => '0');
            shift_reg   <= (others => '0');
        elsif rising_edge(clk) then
            if shifting = '0' then
                -- Reset between frames
                clk_phase_r <= '0';
                bit_cnt     <= (others => '0');
            elsif clk_en = '1' then
                clk_phase_r <= not clk_phase_r;

                if clk_phase_r = '0' then
                    if bit_cnt < to_unsigned(DATA_BITS, C_BIT_CNT_W) then
                        shift_reg <= shift_reg(DATA_BITS - 2 downto 0) & ssi_data;
                        bit_cnt   <= bit_cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end process p_shift;

    -- -------------------------------------------------------------------------
    -- Output latch: capture shift_reg when FSM asserts latch (= DONE state)
    -- -------------------------------------------------------------------------
    p_latch : process (clk, rst_n)
    begin
        if rst_n = '0' then
            data_out <= (others => '0');
        elsif rising_edge(clk) then
            if latch = '1' then
                data_out <= shift_reg;
            end if;
        end if;
    end process p_latch;

    -- Combinational: tell the FSM when the last bit index is reached
    last_bit  <= '1' when bit_cnt = to_unsigned(DATA_BITS, C_BIT_CNT_W)
                 else '0';

    clk_phase <= clk_phase_r;

end architecture rtl;
