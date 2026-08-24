library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Single-clock sample FIFO for the ADC -> moving-average -> Nios V path.
--
-- Input side: Avalon-ST-like ready/valid sample stream.
-- Nios side: Avalon-MM slave, word addressed:
--   address 0: DATA     read-only; reading pops one sample
--   address 1: STATUS   read-only
--   address 2: LEVEL    read-only; number of samples available
--   address 3: CONTROL  write-only
--
-- CONTROL bits:
--   bit 0: flush FIFO
--   bit 1: enable level IRQ
--   bit 2: clear overflow/underflow flags
--
-- STATUS bits:
--   bit 0: empty
--   bit 1: full
--   bit 2: almost full
--   bit 3: almost empty
--   bit 4: overflow; input was valid while FIFO was full
--   bit 5: underflow; Nios read DATA while FIFO was empty
--   bit 6: IRQ enabled
--
entity adc_fifo is
    generic (
        DATA_WIDTH               : positive := 16;
        FIFO_DEPTH               : positive := 1024;
        ALMOST_FULL_THRESHOLD    : positive := 768;
        ALMOST_EMPTY_THRESHOLD   : natural := 4
    );
    port (
        clk                 : in  std_logic;
        reset_n             : in  std_logic;

        -- Avalon-ST-like input from the moving-average IP.
        in_data             : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        in_valid            : in  std_logic;
        in_ready            : out std_logic;

        -- Avalon-MM slave for Nios V.
        avs_address         : in  std_logic_vector(2 downto 0);
        avs_read            : in  std_logic;
        avs_write           : in  std_logic;
        avs_writedata      : in  std_logic_vector(31 downto 0);
        avs_readdata       : out std_logic_vector(31 downto 0);
        avs_waitrequest    : out std_logic;

        -- FIFO status and interrupt.
        level               : out std_logic_vector(31 downto 0);
        empty               : out std_logic;
        full                : out std_logic;
        almost_full         : out std_logic;
        almost_empty        : out std_logic;
        irq                 : out std_logic
    );
end entity adc_fifo;

architecture rtl of adc_fifo is
    type memory_t is array (0 to FIFO_DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);

    function pointer_width(depth : positive) return natural is
        variable width : natural := 0;
        variable value : natural := depth - 1;
    begin
        while value > 0 loop
            width := width + 1;
            value := value / 2;
        end loop;
        if width = 0 then
            return 1;
        end if;
        return width;
    end function;

    constant PTR_WIDTH : natural := pointer_width(FIFO_DEPTH);

    signal memory             : memory_t := (others => (others => '0'));
    signal write_pointer      : unsigned(PTR_WIDTH-1 downto 0) := (others => '0');
    signal read_pointer       : unsigned(PTR_WIDTH-1 downto 0) := (others => '0');
    signal sample_count       : integer range 0 to FIFO_DEPTH := 0;
    signal irq_enable         : std_logic := '0';
    signal overflow_flag      : std_logic := '0';
    signal underflow_flag     : std_logic := '0';

    signal input_push         : std_logic;
    signal mm_pop             : std_logic;
    signal control_flush      : std_logic;
    signal control_clear     : std_logic;
    signal status_word        : std_logic_vector(31 downto 0);

    function next_pointer(pointer : unsigned) return unsigned is
        variable result : unsigned(pointer'range);
    begin
        if to_integer(pointer) = FIFO_DEPTH - 1 then
            result := (others => '0');
        else
            result := pointer + 1;
        end if;
        return result;
    end function;

begin
    -- Never accept a sample while full. This makes overflow observable and
    -- provides backpressure to the moving-average source.
    in_ready <= '1' when sample_count < FIFO_DEPTH else '0';
    input_push <= in_valid and in_ready;

    -- A DATA read consumes one sample. Empty reads are stalled and recorded.
    mm_pop <= '1' when avs_read = '1' and avs_address = "000" and sample_count > 0 else '0';
    avs_waitrequest <= '1' when avs_read = '1' and avs_address = "000" and sample_count = 0 else '0';

    control_flush <= '1' when avs_write = '1' and avs_address = "011" and avs_writedata(0) = '1' else '0';
    control_clear <= '1' when avs_write = '1' and avs_address = "011" and avs_writedata(2) = '1' else '0';

    process(clk, reset_n)
    begin
        if reset_n = '0' then
            write_pointer  <= (others => '0');
            read_pointer   <= (others => '0');
            sample_count   <= 0;
            irq_enable     <= '0';
            overflow_flag  <= '0';
            underflow_flag <= '0';
        elsif rising_edge(clk) then
            if control_flush = '1' then
                write_pointer <= (others => '0');
                read_pointer  <= (others => '0');
                sample_count  <= 0;
            else
                if input_push = '1' then
                    memory(to_integer(write_pointer)) <= in_data;
                    write_pointer <= next_pointer(write_pointer);
                end if;
                if mm_pop = '1' then
                    read_pointer <= next_pointer(read_pointer);
                end if;

                if input_push = '1' and mm_pop = '0' then
                    sample_count <= sample_count + 1;
                elsif input_push = '0' and mm_pop = '1' then
                    sample_count <= sample_count - 1;
                end if;
            end if;

            if avs_write = '1' and avs_address = "011" then
                irq_enable <= avs_writedata(1);
            end if;

            if in_valid = '1' and in_ready = '0' then
                overflow_flag <= '1';
            end if;

            if avs_read = '1' and avs_address = "000" and sample_count = 0 then
                underflow_flag <= '1';
            end if;

            if control_clear = '1' then
                overflow_flag  <= '0';
                underflow_flag <= '0';
            end if;
        end if;
    end process;

    process(sample_count, irq_enable, overflow_flag, underflow_flag)
        variable word : std_logic_vector(31 downto 0);
    begin
        word := (others => '0');
        if sample_count = 0 then
            word(0) := '1';
        end if;
        if sample_count = FIFO_DEPTH then
            word(1) := '1';
        end if;
        if sample_count >= ALMOST_FULL_THRESHOLD then
            word(2) := '1';
        end if;
        if sample_count <= ALMOST_EMPTY_THRESHOLD then
            word(3) := '1';
        end if;
        word(4) := overflow_flag;
        word(5) := underflow_flag;
        word(6) := irq_enable;
        status_word <= word;
    end process;

    process(avs_address, avs_read, sample_count, memory, read_pointer, status_word)
        variable word : std_logic_vector(31 downto 0);
    begin
        word := (others => '0');
        if avs_read = '1' then
            case avs_address is
                when "000" =>
                    word(DATA_WIDTH-1 downto 0) := memory(to_integer(read_pointer));
                when "001" =>
                    word := status_word;
                when "010" =>
                    word := std_logic_vector(to_unsigned(sample_count, 32));
                when others =>
                    word := (others => '0');
            end case;
        end if;
        avs_readdata <= word;
    end process;

    level        <= std_logic_vector(to_unsigned(sample_count, 32));
    empty        <= '1' when sample_count = 0 else '0';
    full         <= '1' when sample_count = FIFO_DEPTH else '0';
    almost_full  <= '1' when sample_count >= ALMOST_FULL_THRESHOLD else '0';
    almost_empty <= '1' when sample_count <= ALMOST_EMPTY_THRESHOLD else '0';
    irq          <= irq_enable and almost_full;

end architecture rtl;
