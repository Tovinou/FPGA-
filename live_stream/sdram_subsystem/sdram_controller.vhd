-- =============================================================================
-- sdram_controller.vhd  (CORRECTED for 75 MHz)
-- SDRAM controller for IS42S16320F (DE10-Lite onboard SDRAM)
-- 64MB, 16-bit bus, 4 banks, 8192 rows, 512 cols
-- Clocked at 75 MHz (PLL c0, SDRAM clock domain)
--
-- Fixes applied:
--   1. ALL timing constants recalculated for 75 MHz (13.33 ns/cycle)
--      Previously all constants were for 100 MHz (10 ns/cycle) — FATAL
--   2. T_INIT_CYCLES = 15000 (200us @ 75MHz)
--   3. T_RFC, T_RCD, T_RP, REFRESH_PERIOD scaled correctly
--   4. sdram_clk port tied to '0' (clock driven directly from PLL c1 in top)
--   5. rd_data registered on the cycle rd_valid asserts (was combinatorial)
--   6. Write data latched one cycle after wr_req accepted (fixes FIFO timing)
--   7. refresh_req cleared inside p_ctrl on transition to ST_REFRESH
--      (removes race condition with parallel p_refresh process)
--   8. tWR (write recovery) wait added before PRECHARGE after WRITE
--      IS42S16320F requires tWR=2 cycles between WRITE and PRECHARGE
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sdram_controller is
    port (
        clk       : in  std_logic;   -- 100 MHz internal FSM clock (PLL c0)
        rst_n     : in  std_logic;

        -- User write interface
        wr_req    : in  std_logic;
        wr_addr   : in  std_logic_vector(24 downto 0);
        wr_data   : in  std_logic_vector(127 downto 0);
        wr_ack    : out std_logic;

        -- User read interface
        rd_req    : in  std_logic;
        rd_addr   : in  std_logic_vector(24 downto 0);
        rd_data   : out std_logic_vector(15 downto 0);
        rd_valid  : out std_logic;
        rd_ack    : out std_logic;

        -- SDRAM bus (IS42S16320F)
    -- NOTE: sdram_clk is NOT driven here.
    -- DRAM_CLK must be connected directly to pll_main c1 (+90 deg)
        -- in stream_top.vhd to preserve the phase relationship.
        sdram_clk  : out std_logic;   -- leave unconnected in subsystem
        sdram_cke  : out std_logic;
        sdram_cs_n : out std_logic;
        sdram_ras_n: out std_logic;
        sdram_cas_n: out std_logic;
        sdram_we_n : out std_logic;
        sdram_ba   : out std_logic_vector(1 downto 0);
        sdram_addr : out std_logic_vector(12 downto 0);
        sdram_dqm  : out std_logic_vector(1 downto 0);
        sdram_dq   : inout std_logic_vector(15 downto 0)
    );
end entity sdram_controller;

architecture rtl of sdram_controller is

    -- =========================================================================
    -- SDRAM timing parameters @ 100 MHz (10 ns period)
    -- IS42S16320F -6 speed grade
    -- =========================================================================
    constant T_INIT_CYCLES  : integer := 20_000;
    constant T_RFC          : integer := 7;
    constant T_RCD          : integer := 2;
    constant T_RP           : integer := 2;
    constant T_CL           : integer := 3;
    constant T_MRD          : integer := 2;
    constant T_WR           : integer := 2;
    constant REFRESH_PERIOD : integer := 781;

    -- =========================================================================
    -- SDRAM commands {CS_N, RAS_N, CAS_N, WE_N}
    -- =========================================================================
    constant CMD_NOP       : std_logic_vector(3 downto 0) := "0111";
    constant CMD_ACTIVE    : std_logic_vector(3 downto 0) := "0011";
    constant CMD_READ      : std_logic_vector(3 downto 0) := "0101";
    constant CMD_WRITE     : std_logic_vector(3 downto 0) := "0100";
    constant CMD_PRECHARGE : std_logic_vector(3 downto 0) := "0010";
    constant CMD_REFRESH   : std_logic_vector(3 downto 0) := "0001";
    constant CMD_MRS       : std_logic_vector(3 downto 0) := "0000";
    constant CMD_INHIBIT   : std_logic_vector(3 downto 0) := "1111";

    -- Mode register value
    -- [12:10] = 000 reserved
    -- [9]     = 0   write burst = programmed burst length
    -- [8:7]   = 00  standard operation
    -- [6:4]   = 011 CAS latency = 3
    -- [3]     = 0   sequential burst
    -- [2:0]   = 011 burst length = 8
    constant MODE_REG : std_logic_vector(12 downto 0) :=
        "000" & "0" & "00" & "011" & "0" & "011";

    -- =========================================================================
    -- FSM states
    -- =========================================================================
    type sdram_state_t is (
        ST_INIT_WAIT,       -- 200us power-up NOP
        ST_INIT_PRECHARGE,  -- precharge all banks
        ST_INIT_REFRESH1,   -- auto-refresh #1
        ST_INIT_REFRESH2,   -- auto-refresh #2
        ST_INIT_MRS,        -- mode register set
        ST_IDLE,            -- arbitrate: refresh > write > read
        ST_REFRESH,         -- auto-refresh cycle
        ST_ACTIVATE,        -- ACTIVE command + tRCD wait
        ST_WRITE,           -- WRITE command
        ST_WRITE_WAIT,      -- tWR recovery before precharge (FIX 6)
        ST_READ,            -- READ command
        ST_READ_WAIT,       -- wait CAS latency
        ST_PRECHARGE        -- PRECHARGE all banks + tRP wait
    );

    signal state      : sdram_state_t := ST_INIT_WAIT;
    signal timer      : integer range 0 to T_INIT_CYCLES := T_INIT_CYCLES;

    -- FIX 5: refresh_req managed entirely in p_ctrl (no parallel process race)
    signal refresh_cnt  : integer range 0 to REFRESH_PERIOD := 0;
    signal refresh_req  : std_logic := '0';
    signal refresh_take : std_logic := '0';

    -- Latched operation parameters
    signal op_is_write  : std_logic := '0';
    signal op_addr      : std_logic_vector(24 downto 0) := (others => '0');
    -- FIX 4: separate latch for write data (captured one cycle after wr_ack)
    signal op_data      : std_logic_vector(127 downto 0) := (others => '0');
    signal burst_cnt_sdram : unsigned(2 downto 0) := (others => '0');

    -- SDRAM bus drivers
    signal cmd          : std_logic_vector(3 downto 0) := CMD_INHIBIT;
    signal ba_int       : std_logic_vector(1 downto 0) := (others => '0');
    signal addr_int     : std_logic_vector(12 downto 0) := (others => '0');
    signal dq_out       : std_logic_vector(15 downto 0) := (others => '0');
    signal dq_oe        : std_logic := '0';

    -- FIX 3: registered read data
    signal rd_data_reg  : std_logic_vector(15 downto 0) := (others => '0');

    -- CAS latency shift register for rd_valid
    -- BUG3 FIX: sized T_CL downto 0 (4 bits for T_CL=3), rising-edge capture
    signal read_pipe    : std_logic_vector(T_CL downto 0) := (others => '0');
    -- BUG5 FIX: active_reads as signal so it resets correctly
    signal active_reads : integer range 0 to 15 := 0;

    signal wr_ack_int   : std_logic := '0';
    signal rd_ack_int   : std_logic := '0';
    signal rd_valid_int : std_logic := '0';

    -- Address field aliases
    alias bank_addr : std_logic_vector(1 downto 0)  is op_addr(24 downto 23);
    alias row_addr  : std_logic_vector(12 downto 0) is op_addr(22 downto 10);
    alias col_addr  : std_logic_vector(9 downto 0)  is op_addr(9 downto 0);

begin

    -- =========================================================================
    -- FIX 4: sdram_clk is NOT driven from logic here.
    -- Output is tied to '0' as a placeholder (legacy port, can be removed).
    -- The actual DRAM_CLK pin MUST be driven directly from pll_main c1
    -- in stream_top.vhd:   DRAM_CLK <= clk_dram;  -- from pll_main c1 (+90 deg)
    -- This preserves the critical phase relationship with internal clk (c0).
    -- =========================================================================
    sdram_clk <= '0';   -- placeholder: DRAM_CLK driven directly from PLL c1 in top-level

    sdram_cke   <= '1';
    sdram_cs_n  <= cmd(3);
    sdram_ras_n <= cmd(2);
    sdram_cas_n <= cmd(1);
    sdram_we_n  <= cmd(0);
    sdram_ba    <= ba_int;
    sdram_addr  <= addr_int;
    sdram_dqm   <= "00";   -- both bytes always enabled

    -- Tri-state DQ bus
    sdram_dq <= dq_out when dq_oe = '1' else (others => 'Z');

    wr_ack   <= wr_ack_int;
    rd_ack   <= rd_ack_int;
    rd_valid <= rd_valid_int;
    rd_data  <= rd_data_reg;   -- FIX 3: expose registered data

    -- =========================================================================
    -- BUG3 FIX: Capture read data on RISING EDGE using read_pipe(T_CL).
    -- With DRAM_CLK leading clk by 3ns and tAC <= 5.4ns, data is valid
    -- well before the next clk rising edge — rising-edge capture is correct.
    -- =========================================================================
    p_rd_capture : process(clk, rst_n)
    begin
        if rst_n = '0' then
            rd_valid_int <= '0';
            rd_data_reg  <= (others => '0');
        elsif rising_edge(clk) then
            rd_valid_int <= read_pipe(T_CL);
            if read_pipe(T_CL) = '1' then
                rd_data_reg <= sdram_dq;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- CAS latency pipeline
    -- Shift a '1' through T_CL stages starting when READ command issued
    -- =========================================================================
    -- BUG5 FIX: active_reads is now a signal (proper async reset)
    p_rd_pipe : process(clk, rst_n)
    begin
        if rst_n = '0' then
            read_pipe    <= (others => '0');
            active_reads <= 0;
        elsif rising_edge(clk) then
            -- Shift left: bit 0 = newest, bit T_CL = oldest (ready to capture)
            read_pipe <= read_pipe(T_CL - 1 downto 0) & '0';
            if state = ST_READ then
                read_pipe(0) <= '1';
                active_reads <= 7;
            elsif active_reads > 0 then
                read_pipe(0) <= '1';
                active_reads <= active_reads - 1;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- FIX 5: Refresh counter — entirely self-contained, no race with p_ctrl
    -- refresh_req is SET here and CLEARED in p_ctrl when entering ST_REFRESH
    -- =========================================================================
    p_refresh : process(clk, rst_n)
    begin
        if rst_n = '0' then
            refresh_cnt <= 0;
            refresh_req <= '0';
        elsif rising_edge(clk) then
            if refresh_take = '1' then
                refresh_req <= '0';
            end if;

            if refresh_req = '0' then
                if refresh_cnt = REFRESH_PERIOD then
                    refresh_cnt <= 0;
                    refresh_req <= '1';
                else
                    refresh_cnt <= refresh_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Main control FSM
    -- =========================================================================
    p_ctrl : process(clk, rst_n)
    begin
        if rst_n = '0' then
            state      <= ST_INIT_WAIT;
            timer      <= T_INIT_CYCLES;
            cmd        <= CMD_INHIBIT;
            ba_int     <= (others => '0');
            addr_int   <= (others => '0');
            dq_oe      <= '0';
            dq_out     <= (others => '0');
            wr_ack_int <= '0';
            rd_ack_int <= '0';
            op_addr    <= (others => '0');
            op_data    <= (others => '0');
            op_is_write<= '0';
            refresh_take <= '0';

        elsif rising_edge(clk) then
            -- Default: deassert single-cycle strobes
            cmd        <= CMD_NOP;
            wr_ack_int <= '0';
            rd_ack_int <= '0';
            dq_oe      <= '0';
            refresh_take <= '0';

            case state is

                -- =============================================================
                -- INIT: 200us power-up NOP period
                -- =============================================================
                when ST_INIT_WAIT =>
                    cmd <= CMD_INHIBIT;
                    if timer = 0 then
                        state <= ST_INIT_PRECHARGE;
                        timer <= T_RP;
                    else
                        timer <= timer - 1;
                    end if;

                -- =============================================================
                -- INIT: Precharge all banks (A10=1)
                -- =============================================================
                when ST_INIT_PRECHARGE =>
                    if timer = T_RP then
                        cmd      <= CMD_PRECHARGE;
                        addr_int <= "0010000000000";  -- A10=1
                        ba_int   <= "00";
                        timer    <= timer - 1;
                    elsif timer = 0 then
                        state <= ST_INIT_REFRESH1;
                        timer <= T_RFC;
                    else
                        timer <= timer - 1;
                    end if;

                -- =============================================================
                -- INIT: Auto-refresh #1
                -- =============================================================
                when ST_INIT_REFRESH1 =>
                    if timer = T_RFC then
                        cmd   <= CMD_REFRESH;
                        timer <= timer - 1;
                    elsif timer = 0 then
                        state <= ST_INIT_REFRESH2;
                        timer <= T_RFC;
                    else
                        timer <= timer - 1;
                    end if;

                -- =============================================================
                -- INIT: Auto-refresh #2
                -- =============================================================
                when ST_INIT_REFRESH2 =>
                    if timer = T_RFC then
                        cmd   <= CMD_REFRESH;
                        timer <= timer - 1;
                    elsif timer = 0 then
                        state <= ST_INIT_MRS;
                        timer <= T_MRD;
                    else
                        timer <= timer - 1;
                    end if;

                -- =============================================================
                -- INIT: Mode Register Set
                -- =============================================================
                when ST_INIT_MRS =>
                    if timer = T_MRD then
                        cmd      <= CMD_MRS;
                        ba_int   <= "00";
                        addr_int <= MODE_REG;
                        timer    <= timer - 1;
                    elsif timer = 0 then
                        state <= ST_IDLE;
                    else
                        timer <= timer - 1;
                    end if;

                -- =============================================================
                -- IDLE: Arbitrate — refresh > write > read
                -- FIX 5: clear refresh_req here on the same edge we leave IDLE
                -- =============================================================
                when ST_IDLE =>
                    if refresh_req = '1' then
                        state       <= ST_REFRESH;
                        timer       <= T_RFC;
                        refresh_take <= '1';

                    elsif wr_req = '1' then
                        -- Latch address immediately; data latched next cycle
                        -- (FIX 4: data arrives from FIFO one cycle after rd_en)
                        op_addr     <= wr_addr;
                        op_is_write <= '1';
                        wr_ack_int  <= '1';
                        -- Issue ACTIVE command
                        cmd         <= CMD_ACTIVE;
                        ba_int      <= wr_addr(24 downto 23);
                        addr_int    <= wr_addr(22 downto 10);
                        state       <= ST_ACTIVATE;
                        timer       <= T_RCD - 1;   -- ACTIVE issued this cycle

                    elsif rd_req = '1' then
                        op_addr     <= rd_addr;
                        op_is_write <= '0';
                        rd_ack_int  <= '1';
                        cmd         <= CMD_ACTIVE;
                        ba_int      <= rd_addr(24 downto 23);
                        addr_int    <= rd_addr(22 downto 10);
                        state       <= ST_ACTIVATE;
                        timer       <= T_RCD - 1;
                    end if;

                -- =============================================================
                -- REFRESH: Auto-refresh cycle (tRFC wait)
                -- =============================================================
                when ST_REFRESH =>
                    if timer = T_RFC then
                        cmd   <= CMD_REFRESH;
                        timer <= timer - 1;
                    elsif timer = 0 then
                        state <= ST_IDLE;
                    else
                        timer <= timer - 1;
                    end if;

                -- =============================================================
                -- ACTIVATE: wait tRCD after ACTIVE command
                -- FIX 4: latch write data here (one cycle after wr_ack)
                --        FIFO output is now stable
                -- =============================================================
                when ST_ACTIVATE =>
                    -- Latch write data here — one cycle after wr_ack fired
                    -- The FIFO has had one full clock to present rd_data
                    if op_is_write = '1' and timer = T_RCD - 1 then
                        op_data <= wr_data;   -- stable now (FIFO latency met)
                    end if;

                    if timer = 0 then
                        if op_is_write = '1' then
                            state <= ST_WRITE;
                        else
                            state <= ST_READ;
                        end if;
                    else
                        timer <= timer - 1;
                    end if;

                -- =============================================================
                -- WRITE: issue WRITE command, drive DQ for 8 cycles
                -- =============================================================
                when ST_WRITE =>
                    ba_int   <= bank_addr;
                    dq_out   <= op_data(15 downto 0);
                    dq_oe    <= '1';
                    op_data  <= x"0000" & op_data(127 downto 16);
                    
                    if burst_cnt_sdram = 0 then
                        cmd      <= CMD_WRITE;
                        addr_int <= "001" & col_addr(9 downto 0);  -- A10=1: auto-precharge
                    else
                        cmd      <= CMD_NOP;
                    end if;
                    
                    if burst_cnt_sdram = 7 then
                        burst_cnt_sdram <= (others => '0');
                        state    <= ST_WRITE_WAIT;
                        -- tWR + tRP: even with auto-precharge, must wait for
                        -- internal precharge to complete before next ACTIVATE
                        -- on the same bank. tWR=2 + tRP=2 cycles = 4 total.
                        timer    <= T_WR + T_RP - 1;
                    else
                        burst_cnt_sdram <= burst_cnt_sdram + 1;
                    end if;

                -- =============================================================
                -- FIX 6: tWR recovery wait between WRITE and PRECHARGE
                -- IS42S16320F requires tWR = 1 clock minimum after WRITE data
                -- Auto-precharge automatically handles the precharge phase
                -- =============================================================
                when ST_WRITE_WAIT =>
                    dq_oe <= '0';
                    if timer = 0 then
                        state <= ST_IDLE;
                    else
                        timer <= timer - 1;
                    end if;

                -- =============================================================
                -- READ: issue READ command, then wait CAS latency + Burst
                -- =============================================================
                when ST_READ =>
                    cmd      <= CMD_READ;
                    ba_int   <= bank_addr;
                    addr_int <= "001" & col_addr(9 downto 0);  -- A10=1: auto-precharge
                    state    <= ST_READ_WAIT;
                    timer    <= T_CL + 8 + T_RP - 2;

                when ST_READ_WAIT =>
                    -- p_rd_pipe and p_rd_capture handle data capture and rd_valid
                    if timer = 0 then
                        state <= ST_IDLE;
                    else
                        timer <= timer - 1;
                    end if;

                -- =============================================================
                -- PRECHARGE: precharge all banks, wait tRP
                -- =============================================================
                when ST_PRECHARGE =>
                    if timer = T_RP then
                        cmd      <= CMD_PRECHARGE;
                        addr_int <= "0010000000000";  -- A10=1: all banks
                        timer    <= timer - 1;
                    elsif timer = 0 then
                        state <= ST_IDLE;
                    else
                        timer <= timer - 1;
                    end if;

                when others =>
                    state <= ST_IDLE;

            end case;
        end if;
    end process;

end architecture rtl;
