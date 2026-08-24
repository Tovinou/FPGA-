-- =============================================================================
-- ssi_fsm.vhd
-- SSI Master Finite State Machine
--
-- Sequences the SSI transaction:
--   IDLE → ST_START → SHIFTING → DONE → MONOFLOP → IDLE
--
-- Inputs
--   start     : external trigger (one sys-clock pulse)
--   clk_en    : half-period tick from ssi_clk_div
--   clk_phase : current SSI half-cycle phase from ssi_shift (0=low, 1=high)
--   last_bit  : from ssi_shift; high when the final bit index is reached
--
-- Outputs
--   state     : current FSM state (shared with ssi_clk_out via ssi_master)
--   active    : HIGH in ST_START + SHIFTING; enables ssi_clk_div
--   busy      : HIGH whenever a transaction is in progress
--   valid     : single sys-clock pulse when data is ready (DONE state)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;
use work.ssi_pkg.all;

entity ssi_fsm is
    generic (
        CLK_FREQ_HZ : positive := 50_000_000;
        DATA_BITS   : positive := 25
    );
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;
        -- Control
        start     : in  std_logic;
        -- From ssi_clk_div
        clk_en    : in  std_logic;
        -- From ssi_shift
        clk_phase : in  std_logic;
        last_bit  : in  std_logic;
        -- Outputs
        state     : out t_ssi_state;
        active    : out std_logic;
        busy      : out std_logic;
        valid     : out std_logic
    );
end entity ssi_fsm;

architecture rtl of ssi_fsm is

    -- Monoflop inter-frame delay: 25 µs
    constant C_MONO_CYCLES : positive :=
        integer(real(CLK_FREQ_HZ) / 1_000_000.0) * 25;
    constant C_MONO_W      : positive :=
        integer(ceil(log2(real(C_MONO_CYCLES + 1))));

    signal state_r      : t_ssi_state := IDLE;
    signal next_state_c : t_ssi_state := IDLE;
    signal mono_cnt     : unsigned(C_MONO_W - 1 downto 0) := (others => '0');

begin

    -- -------------------------------------------------------------------------
    -- Sequential state register
    -- -------------------------------------------------------------------------
    p_state : process (clk, rst_n)
    begin
        if rst_n = '0' then
            state_r <= IDLE;
        elsif rising_edge(clk) then
            state_r <= next_state_c;
        end if;
    end process p_state;

    -- -------------------------------------------------------------------------
    -- Next-state combinational logic
    -- -------------------------------------------------------------------------
    p_next : process (state_r, start, clk_en, clk_phase, last_bit, mono_cnt)
    begin
        next_state_c <= state_r;        -- default: stay in current state
        case state_r is

            when IDLE =>
                if start = '1' then
                    next_state_c <= ST_START;
                end if;

            when ST_START =>
                if clk_en = '1' then
                    next_state_c <= SHIFTING;
                end if;

            when SHIFTING =>
                if clk_en = '1' and clk_phase = '1' and last_bit = '1' then
                    next_state_c <= DONE;
                end if;

            when DONE =>
                next_state_c <= MONOFLOP;

            when MONOFLOP =>
                if mono_cnt = to_unsigned(C_MONO_CYCLES - 1, C_MONO_W) then
                    next_state_c <= IDLE;
                end if;

        end case;
    end process p_next;

    -- -------------------------------------------------------------------------
    -- Monoflop counter
    -- -------------------------------------------------------------------------
    p_mono : process (clk, rst_n)
    begin
        if rst_n = '0' then
            mono_cnt <= (others => '0');
        elsif rising_edge(clk) then
            if state_r = MONOFLOP then
                mono_cnt <= mono_cnt + 1;
            else
                mono_cnt <= (others => '0');
            end if;
        end if;
    end process p_mono;

    -- -------------------------------------------------------------------------
    -- Registered outputs
    -- -------------------------------------------------------------------------
    p_out : process (clk, rst_n)
    begin
        if rst_n = '0' then
            busy  <= '0';
            valid <= '0';
        elsif rising_edge(clk) then
            -- valid: one-cycle pulse — DONE always lasts exactly one cycle
            if state_r = DONE then
                valid <= '1';
            else
                valid <= '0';
            end if;

            if state_r = IDLE then
                busy <= '0';
            else
                busy <= '1';
            end if;
        end if;
    end process p_out;

    -- active is combinational (needed immediately by clk_div)
    active <= '1' when (state_r = ST_START or state_r = SHIFTING) else '0';

    state  <= state_r;

end architecture rtl;
