-- =============================================================================
-- i2c_top.vhd  (CORRECTED)
-- SCCB (I2C-compatible) master for OV7670 register initialisation
--
-- Fixes applied:
--   1. HALF_PERIOD corrected for 24 MHz input clock (was designed for 50 MHz)
--      24MHz / (120*2) = 100 kHz SCCB
--   2. Post-soft-reset delay added (1ms after COM7=0x80 before next write)
--   3. Reset hold extended to 5ms (was 1ms, OV7670 datasheet recommends >=1ms)
--   4. SDA/SCL open-drain drive: 'Z' when idle (not '1')
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity i2c_top is
    port (
        clk       : in    std_logic;   -- 25 MHz (pll_main c2)
        rst_n     : in    std_logic;
        -- SCCB bus (open-drain, external pull-ups required)
        sioc      : out   std_logic;
        siod      : inout std_logic;
        -- Status
        done      : out   std_logic;   -- '1' when all registers written
        cam_rst_n : out   std_logic;   -- OV7670 RESETB (active low)
        cam_pwdn  : out   std_logic;   -- OV7670 PWDN   ('0' = powered)
        reg_cfg0_dbg : out std_logic_vector(31 downto 0);
        reg_cfg1_dbg : out std_logic_vector(31 downto 0);
        reg_cfg2_dbg : out std_logic_vector(31 downto 0);
        reg_cfg3_dbg : out std_logic_vector(31 downto 0)
    );
end entity i2c_top;

architecture rtl of i2c_top is

    -- -------------------------------------------------------------------------
    -- SCCB timing
    -- Input clock: 25 MHz  (pll_main c2) -> period = 40 ns
    -- Target SCCB: 50 kHz -> half-period = 10000 ns = 250 clock cycles
    -- -------------------------------------------------------------------------
    constant HALF_PERIOD      : integer := 250;

    -- 1ms delay at 25MHz = 25000 cycles
    constant DELAY_1MS        : integer := 25_000;
    -- 5ms reset hold at 25MHz = 125000 cycles
    constant RESET_HOLD_CYCLES: integer := 125_000;

    -- OV7670 SCCB write address
    constant OV7670_WRITE_ADDR : std_logic_vector(7 downto 0) := x"42";
    constant OV7670_READ_ADDR  : std_logic_vector(7 downto 0) := x"43";

    -- -------------------------------------------------------------------------
    -- Register init table
    -- IMPORTANT: index 0 MUST be the soft reset (0x12=0x80)
    -- A 1ms delay is inserted automatically after index 0 before writing index 1
    -- -------------------------------------------------------------------------
    type reg_pair is record
        addr : std_logic_vector(7 downto 0);
        data : std_logic_vector(7 downto 0);
    end record;

    type reg_table_t is array (natural range <>) of reg_pair;
    type byte_table_t is array (natural range <>) of std_logic_vector(7 downto 0);

    constant REG_TABLE : reg_table_t := (
        -- [0] Soft reset — 1ms delay inserted after this automatically
        (x"12", x"80"),  -- COM7: reset all registers

        -- Clock
        (x"6B", x"0A"),  -- DBLV: bypass internal PLL (more stable on long wiring)
        (x"11", x"01"),  -- CLKRC: prescaler /2

        -- Output format: RGB565
        (x"12", x"14"),  -- COM7: QVGA + RGB mode (Color Bar disabled)
        (x"40", x"D0"),  -- COM15: RGB565, full output range 0x00..0xFF
        -- Normal operation: disable internal color bar test pattern
        (x"42", x"00"),  -- COM17: normal video
        (x"8C", x"00"),  -- RGB444: disable
        (x"3A", x"04"),  -- TSLB: swap RGB byte order (bit3=1) for correct RGB565 output
        (x"3D", x"83"),  -- COM13: gamma(bit7) + UV saturation auto(bit1) + UV swap(bit0) for correct RGB565
        
        -- Color Matrix: standard YUV->RGB coefficients (from Linux OV7670 kernel driver)
        (x"4f", x"80"),  -- MTX1
        (x"50", x"80"),  -- MTX2
        (x"51", x"00"),  -- MTX3
        (x"52", x"22"),  -- MTX4
        (x"53", x"5e"),  -- MTX5
        (x"54", x"80"),  -- MTX6
        (x"58", x"9e"),  -- MTXS (bit7=auto-adjust, bits5:4=sign MTX5 neg, bits3=sign MTX4 neg)

        -- Resolution: 320x240 (QVGA, downsample from VGA)
        (x"0C", x"04"),  -- COM3: enable DCW
        (x"3E", x"19"),  -- COM14: manual scaling, PCLK divided
        (x"70", x"3A"),  -- SCALING_XSC
        (x"71", x"35"),  -- SCALING_YSC
        (x"72", x"11"),  -- SCALING_DCWCTR: downsample by 2
        (x"73", x"F1"),  -- SCALING_PCLK_DIV
        (x"A2", x"02"),  -- SCALING_PCLK_DELAY
        -- Active window (QVGA)
        (x"17", x"16"),  -- HSTART
        (x"18", x"04"),  -- HSTOP
        (x"32", x"A4"),  -- HREF
        (x"19", x"02"),  -- VSTART
        (x"1A", x"7A"),  -- VSTOP
        (x"03", x"0A"),  -- VREF

        (x"13", x"E7"),  -- COM8: enable AGC/AWB/AEC
        (x"0D", x"40"),  -- COM4
        (x"14", x"18"),  -- COM9: restore normal AGC ceiling

        -- COM10: VSYNC active-low during frame (bit2=1), HREF active-high (bit3=0), PCLK inverted (bit4=1)
        (x"15", x"14"),

        -- Sentinel (must be last)
        (x"FF", x"FF")
    );

    constant READ_TABLE : byte_table_t := (
        x"12", x"40", x"42", x"8C",  -- COM7, COM15, COM17, RGB444
        x"3A", x"3D", x"0C", x"3E",  -- TSLB, COM13, COM3, COM14
        x"70", x"71", x"72", x"73",  -- scaling registers
        x"A2", x"11", x"6B", x"15"   -- PCLK delay, CLKRC, DBLV, COM10
    );

    -- -------------------------------------------------------------------------
    -- FSM states
    -- -------------------------------------------------------------------------
    type i2c_state_t is (
        ST_RESET_HOLD,       -- hold OV7670 in hardware reset
        ST_RESET_RELEASE,    -- release reset, wait for camera ready
        ST_SOFT_RST_WAIT,    -- 1ms wait after soft reset register write
        ST_IDLE,             -- check next register to send
        ST_START,            -- I2C START condition
        ST_SEND_BYTE,        -- send 8 bits MSB first
        ST_ACK,              -- ACK slot (SCCB: don't-care, release SDA)
        ST_STOP,             -- I2C STOP condition
        ST_NEXT_REG,         -- advance register index
        ST_READ_BYTE,        -- read 8 bits from SIOD
        ST_READ_NACK,        -- NACK the read byte
        ST_READ_STORE,       -- latch the read byte and advance
        ST_DONE              -- all registers written, idle forever
    );

    type txn_mode_t is (TXN_INIT_WRITE, TXN_READ_PHASE0, TXN_READ_PHASE1);
    type stop_action_t is (STOP_TO_NEXT_REG, STOP_TO_READ_PHASE1, STOP_TO_READ_STORE);

    signal state       : i2c_state_t := ST_RESET_HOLD;
    signal clk_cnt     : integer range 0 to HALF_PERIOD   := 0;
    signal delay_cnt   : integer range 0 to DELAY_1MS     := 0;
    signal reset_cnt   : integer range 0 to RESET_HOLD_CYCLES := 0;
    signal bit_cnt     : integer range 0 to 7 := 7;
    signal byte_idx    : integer range 0 to 2 := 0;
    signal reg_idx     : integer range 0 to REG_TABLE'length-1 := 0;
    signal read_idx    : integer range 0 to READ_TABLE'length := 0;
    signal shift_reg   : std_logic_vector(7 downto 0) := (others => '0');
    signal read_shift  : std_logic_vector(7 downto 0) := (others => '0');
    signal scl_int     : std_logic := '1';
    signal sda_int     : std_logic := '1';
    signal tick        : std_logic := '0';
    signal done_int    : std_logic := '0';
    signal start_phase : std_logic := '0';
    signal stop_phase  : std_logic := '0';
    signal read_subphase : std_logic := '0';
    signal txn_mode    : txn_mode_t := TXN_INIT_WRITE;
    signal stop_action : stop_action_t := STOP_TO_NEXT_REG;
    signal readback_data : byte_table_t(0 to READ_TABLE'length-1) := (others => (others => '0'));

begin

    cam_pwdn <= '0';      -- always powered
    done     <= done_int;
    reg_cfg0_dbg <= readback_data(0) & readback_data(1) & readback_data(2) & readback_data(3);
    reg_cfg1_dbg <= readback_data(4) & readback_data(5) & readback_data(6) & readback_data(7);
    reg_cfg2_dbg <= readback_data(8) & readback_data(9) & readback_data(10) & readback_data(11);
    reg_cfg3_dbg <= readback_data(12) & readback_data(13) & readback_data(14) & readback_data(15);

    -- Open-drain outputs: drive low or release (Z = pulled high externally)
    sioc <= '0' when scl_int = '0' else 'Z';
    siod <= '0' when sda_int = '0' else 'Z';

    -- -------------------------------------------------------------------------
    -- SCCB clock tick: pulses '1' once every HALF_PERIOD cycles
    -- -------------------------------------------------------------------------
    p_tick : process(clk)
    begin
        if rising_edge(clk) then
            tick <= '0';
            if clk_cnt = HALF_PERIOD - 1 then
                clk_cnt <= 0;
                tick    <= '1';
            else
                clk_cnt <= clk_cnt + 1;
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- Main FSM
    -- -------------------------------------------------------------------------
    p_fsm : process(clk, rst_n)
    begin
        if rst_n = '0' then
            state      <= ST_RESET_HOLD;
            reset_cnt  <= 0;
            delay_cnt  <= 0;
            cam_rst_n  <= '0';
            scl_int    <= '1';
            sda_int    <= '1';
            done_int   <= '0';
            reg_idx    <= 0;
            read_idx   <= 0;
            byte_idx   <= 0;
            bit_cnt    <= 7;
            shift_reg  <= (others => '0');
            read_shift <= (others => '0');
            start_phase <= '0';
            stop_phase  <= '0';
            read_subphase <= '0';
            txn_mode   <= TXN_INIT_WRITE;
            stop_action <= STOP_TO_NEXT_REG;
            readback_data <= (others => (others => '0'));

        elsif rising_edge(clk) then

            case state is

                -- -------------------------------------------------------------
                -- Hold OV7670 RESETB low for 5ms minimum
                -- -------------------------------------------------------------
                when ST_RESET_HOLD =>
                    cam_rst_n <= '0';
                    scl_int   <= '1';
                    sda_int   <= '1';
                    if reset_cnt = RESET_HOLD_CYCLES - 1 then
                        reset_cnt <= 0;
                        state     <= ST_RESET_RELEASE;
                    else
                        reset_cnt <= reset_cnt + 1;
                    end if;

                -- -------------------------------------------------------------
                -- Release RESETB, wait another 5ms before sending SCCB
                -- (OV7670 needs time to initialise internal state after reset)
                -- -------------------------------------------------------------
                when ST_RESET_RELEASE =>
                    cam_rst_n <= '1';
                    if reset_cnt = RESET_HOLD_CYCLES - 1 then
                        reset_cnt <= 0;
                        state     <= ST_IDLE;
                    else
                        reset_cnt <= reset_cnt + 1;
                    end if;

                -- -------------------------------------------------------------
                -- 1ms wait after soft reset (COM7=0x80, reg_idx was 0)
                -- -------------------------------------------------------------
                when ST_SOFT_RST_WAIT =>
                    scl_int <= '1';
                    sda_int <= '1';
                    if delay_cnt = DELAY_1MS - 1 then
                        delay_cnt <= 0;
                        state     <= ST_IDLE;
                    else
                        delay_cnt <= delay_cnt + 1;
                    end if;

                -- -------------------------------------------------------------
                -- Idle: check next register or finish
                -- -------------------------------------------------------------
                when ST_IDLE =>
                    scl_int <= '1';
                    sda_int <= '1';
                    if tick = '1' then
                        if REG_TABLE(reg_idx).addr /= x"FF" then
                            txn_mode   <= TXN_INIT_WRITE;
                            byte_idx   <= 0;
                            shift_reg  <= OV7670_WRITE_ADDR;
                            bit_cnt    <= 7;
                            start_phase <= '0';
                            state      <= ST_START;
                        elsif read_idx < READ_TABLE'length then
                            byte_idx   <= 0;
                            bit_cnt    <= 7;
                            start_phase <= '0';
                            if read_subphase = '0' then
                                txn_mode  <= TXN_READ_PHASE0;
                                shift_reg <= OV7670_WRITE_ADDR;
                            else
                                txn_mode  <= TXN_READ_PHASE1;
                                shift_reg <= OV7670_READ_ADDR;
                            end if;
                            state <= ST_START;
                        else
                            state    <= ST_DONE;
                            done_int <= '1';
                        end if;
                    end if;

                -- -------------------------------------------------------------
                -- START: SDA falls while SCL high
                -- -------------------------------------------------------------
                when ST_START =>
                    if tick = '1' then
                        if start_phase = '0' then
                            scl_int     <= '1';
                            sda_int     <= '0';
                            start_phase <= '1';
                        else
                            scl_int     <= '0';
                            sda_int     <= shift_reg(7);
                            start_phase <= '0';
                            state       <= ST_SEND_BYTE;
                        end if;
                    end if;

                -- -------------------------------------------------------------
                -- Send 8 bits MSB first, one bit per tick
                -- -------------------------------------------------------------
                when ST_SEND_BYTE =>
                    if tick = '1' then
                        if scl_int = '0' then
                            scl_int <= '1';
                        else
                            scl_int <= '0';
                            if bit_cnt = 0 then
                                sda_int <= '1';
                                state   <= ST_ACK;
                            else
                                sda_int    <= shift_reg(6);
                                shift_reg  <= shift_reg(6 downto 0) & '0';
                                bit_cnt    <= bit_cnt - 1;
                            end if;
                        end if;
                    end if;

                -- -------------------------------------------------------------
                -- ACK slot: release SDA, one SCL pulse (SCCB don't-care)
                -- Then load next byte or go to STOP
                -- -------------------------------------------------------------
                when ST_ACK =>
                    if tick = '1' then
                        if scl_int = '0' then
                            scl_int <= '1';
                        else
                            scl_int <= '0';
                            case txn_mode is
                                when TXN_INIT_WRITE =>
                                    case byte_idx is
                                        when 0 =>   -- just sent device addr, load reg addr
                                            shift_reg <= REG_TABLE(reg_idx).addr;
                                            byte_idx  <= 1;
                                            bit_cnt   <= 7;
                                            sda_int   <= REG_TABLE(reg_idx).addr(7);
                                            state     <= ST_SEND_BYTE;
                                        when 1 =>   -- just sent reg addr, load data
                                            shift_reg <= REG_TABLE(reg_idx).data;
                                            byte_idx  <= 2;
                                            bit_cnt   <= 7;
                                            sda_int   <= REG_TABLE(reg_idx).data(7);
                                            state     <= ST_SEND_BYTE;
                                        when others =>  -- just sent data, stop
                                            sda_int     <= '0';
                                            stop_phase  <= '0';
                                            stop_action <= STOP_TO_NEXT_REG;
                                            state       <= ST_STOP;
                                    end case;

                                when TXN_READ_PHASE0 =>
                                    case byte_idx is
                                        when 0 =>
                                            shift_reg <= READ_TABLE(read_idx);
                                            byte_idx  <= 1;
                                            bit_cnt   <= 7;
                                            sda_int   <= READ_TABLE(read_idx)(7);
                                            state     <= ST_SEND_BYTE;
                                        when others =>
                                            sda_int      <= '0';
                                            stop_phase   <= '0';
                                            stop_action  <= STOP_TO_READ_PHASE1;
                                            state        <= ST_STOP;
                                    end case;

                                when TXN_READ_PHASE1 =>
                                    sda_int    <= '1';
                                    bit_cnt    <= 7;
                                    read_shift <= (others => '0');
                                    state      <= ST_READ_BYTE;
                            end case;
                        end if;
                    end if;

                when ST_READ_BYTE =>
                    if tick = '1' then
                        sda_int <= '1';
                        if scl_int = '0' then
                            scl_int <= '1';
                        else
                            if siod = '0' then
                                read_shift(bit_cnt) <= '0';
                            else
                                read_shift(bit_cnt) <= '1';
                            end if;
                            scl_int <= '0';
                            if bit_cnt = 0 then
                                state <= ST_READ_NACK;
                            else
                                bit_cnt <= bit_cnt - 1;
                            end if;
                        end if;
                    end if;

                when ST_READ_NACK =>
                    if tick = '1' then
                        if scl_int = '0' then
                            sda_int <= '1';
                            scl_int <= '1';
                        else
                            scl_int     <= '0';
                            sda_int     <= '0';
                            stop_phase  <= '0';
                            stop_action <= STOP_TO_READ_STORE;
                            state       <= ST_STOP;
                        end if;
                    end if;

                -- -------------------------------------------------------------
                -- STOP: SCL rises then SDA rises (while SCL high)
                -- -------------------------------------------------------------
                when ST_STOP =>
                    if tick = '1' then
                        if stop_phase = '0' then
                            scl_int    <= '1';
                            sda_int    <= '0';
                            stop_phase <= '1';
                        else
                            scl_int    <= '1';
                            sda_int    <= '1';
                            stop_phase <= '0';
                            case stop_action is
                                when STOP_TO_NEXT_REG =>
                                    state <= ST_NEXT_REG;
                                when STOP_TO_READ_PHASE1 =>
                                    read_subphase <= '1';
                                    state <= ST_IDLE;
                                when STOP_TO_READ_STORE =>
                                    state <= ST_READ_STORE;
                            end case;
                        end if;
                    end if;

                -- -------------------------------------------------------------
                -- Advance reg_idx; insert 1ms wait after soft reset (idx=0)
                -- -------------------------------------------------------------
                when ST_NEXT_REG =>
                    if tick = '1' then
                        if reg_idx = 0 then
                            -- Soft reset just written — mandatory 1ms wait
                            reg_idx   <= reg_idx + 1;
                            delay_cnt <= 0;
                            state     <= ST_SOFT_RST_WAIT;
                        else
                            reg_idx <= reg_idx + 1;
                            state   <= ST_IDLE;
                        end if;
                    end if;

                when ST_READ_STORE =>
                    if tick = '1' then
                        readback_data(read_idx) <= read_shift;
                        read_subphase <= '0';
                        if read_idx = READ_TABLE'length - 1 then
                            read_idx  <= READ_TABLE'length;
                            done_int  <= '1';
                            state     <= ST_DONE;
                        else
                            read_idx <= read_idx + 1;
                            state    <= ST_IDLE;
                        end if;
                    end if;

                -- -------------------------------------------------------------
                -- Done: hold SCL/SDA high, assert done forever
                -- -------------------------------------------------------------
                when ST_DONE =>
                    scl_int  <= '1';
                    sda_int  <= '1';
                    done_int <= '1';

                when others =>
                    state <= ST_IDLE;

            end case;
        end if;
    end process;

end architecture rtl;
