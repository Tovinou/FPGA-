library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Hardware reader for the Modular ADC sample-store CSR.
--
-- The reader is an Avalon-MM master. It waits for the sample-store status
-- bit, reads the 64 configured sample slots, extracts CH0 bits [11:0], and
-- emits one Avalon-ST sample at a time.
entity adc_reader is
    generic (
        SAMPLE_SLOTS : positive := 64
    );
    port (
        clk                 : in  std_logic;
        reset_n             : in  std_logic;
        enable              : in  std_logic;
        busy                : out std_logic;

        -- Avalon-MM master to modular_adc_0.sample_store_csr.
        adc_address         : out std_logic_vector(6 downto 0);
        adc_read            : out std_logic;
        adc_write           : out std_logic;
        adc_writedata       : out std_logic_vector(31 downto 0);
        adc_readdata        : in  std_logic_vector(31 downto 0);
        adc_waitrequest     : in  std_logic;

        -- Avalon-ST source to moving_average.
        sample_data         : out std_logic_vector(11 downto 0);
        sample_valid        : out std_logic;
        sample_ready        : in  std_logic
    );
end entity adc_reader;

architecture rtl of adc_reader is
    constant IRQ_ENABLE_ADDRESS : unsigned(6 downto 0) := to_unsigned(16#40#, 7);
    constant IRQ_STATUS_ADDRESS : unsigned(6 downto 0) := to_unsigned(16#41#, 7);

    type state_type is (
        IDLE,
        INIT_IRQ,
        WAIT_IRQ,
        READ_IRQ_STATUS,
        READ_SAMPLE,
        PRESENT_SAMPLE,
        CLEAR_IRQ
    );

    signal state          : state_type := IDLE;
    signal slot_index     : integer range 0 to SAMPLE_SLOTS-1 := 0;
    signal sample_reg     : std_logic_vector(11 downto 0) := (others => '0');
    signal busy_reg       : std_logic := '0';

begin
    busy <= busy_reg;

    process(clk, reset_n)
    begin
        if reset_n = '0' then
            state      <= IDLE;
            slot_index <= 0;
            sample_reg <= (others => '0');
            busy_reg   <= '0';
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    busy_reg <= '0';
                    if enable = '1' then
                        state <= INIT_IRQ;
                    end if;

                when INIT_IRQ =>
                    busy_reg <= '1';
                    if enable = '0' then
                        state <= IDLE;
                    elsif adc_waitrequest = '0' then
                        state <= WAIT_IRQ;
                    end if;

                when WAIT_IRQ =>
                    busy_reg <= '1';
                    if enable = '0' then
                        state <= IDLE;
                    else
                        state <= READ_IRQ_STATUS;
                    end if;

                when READ_IRQ_STATUS =>
                    busy_reg <= '1';
                    if enable = '0' then
                        state <= IDLE;
                    elsif adc_waitrequest = '0' then
                        if adc_readdata(0) = '1' then
                            slot_index <= 0;
                            state <= READ_SAMPLE;
                        else
                            state <= WAIT_IRQ;
                        end if;
                    end if;

                when READ_SAMPLE =>
                    busy_reg <= '1';
                    if enable = '0' then
                        state <= IDLE;
                    elsif adc_waitrequest = '0' then
                        sample_reg <= adc_readdata(11 downto 0);
                        state <= PRESENT_SAMPLE;
                    end if;

                when PRESENT_SAMPLE =>
                    busy_reg <= '1';
                    if enable = '0' then
                        state <= IDLE;
                    elsif sample_ready = '1' then
                        if slot_index = SAMPLE_SLOTS - 1 then
                            state <= CLEAR_IRQ;
                        else
                            slot_index <= slot_index + 1;
                            state <= READ_SAMPLE;
                        end if;
                    end if;

                when CLEAR_IRQ =>
                    busy_reg <= '1';
                    if enable = '0' then
                        state <= IDLE;
                    elsif adc_waitrequest = '0' then
                        state <= WAIT_IRQ;
                    end if;
            end case;
        end if;
    end process;

    -- Avalon-MM master request generation.
    process(state, slot_index)
    begin
        adc_address   <= (others => '0');
        adc_read      <= '0';
        adc_write     <= '0';
        adc_writedata <= (others => '0');

        case state is
            when INIT_IRQ =>
                adc_address <= std_logic_vector(IRQ_ENABLE_ADDRESS);
                adc_write <= '1';
                adc_writedata(0) <= '1';

            when READ_IRQ_STATUS =>
                adc_address <= std_logic_vector(IRQ_STATUS_ADDRESS);
                adc_read <= '1';

            when READ_SAMPLE =>
                adc_address <= std_logic_vector(to_unsigned(slot_index, 7));
                adc_read <= '1';

            when CLEAR_IRQ =>
                adc_address <= std_logic_vector(IRQ_STATUS_ADDRESS);
                adc_write <= '1';
                adc_writedata(0) <= '1';

            when others =>
                null;
        end case;
    end process;

    sample_data  <= sample_reg;
    sample_valid <= '1' when state = PRESENT_SAMPLE else '0';

end architecture rtl;
