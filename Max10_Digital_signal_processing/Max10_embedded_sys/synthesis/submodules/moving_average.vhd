library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Streaming moving-average filter for the MAX 10 ADC path.
entity moving_average is
    generic (
        TAPS    : positive := 16;
        DATA_W  : positive := 12;
        COEF_W  : positive := 8;
        ACC_W   : positive := 20
    );
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;
        data_in   : in  std_logic_vector(DATA_W-1 downto 0);
        valid_in  : in  std_logic;
        ready_in  : out std_logic;
        data_out  : out std_logic_vector(15 downto 0);
        valid_out : out std_logic;
        ready_out : in  std_logic
    );
end moving_average;

architecture rtl of moving_average is
    type sample_array is array (0 to TAPS-1) of unsigned(DATA_W-1 downto 0);

    signal samples          : sample_array := (others => (others => '0'));
    signal accumulator      : unsigned(ACC_W-1 downto 0) := (others => '0');
    signal write_pointer    : integer range 0 to TAPS-1 := 0;
    signal output_data_reg  : std_logic_vector(15 downto 0) := (others => '0');
    signal output_valid_reg : std_logic := '0';
    signal input_ready_int  : std_logic;
    signal input_accept     : std_logic;
    signal output_consume   : std_logic;

begin
    input_ready_int <= not output_valid_reg or ready_out;
    ready_in <= input_ready_int;
    input_accept <= valid_in and input_ready_int;
    output_consume <= output_valid_reg and ready_out;

    process(clk, rst_n)
        variable next_acc       : unsigned(ACC_W-1 downto 0);
        variable average_value  : unsigned(ACC_W-1 downto 0);
        variable old_sample_acc : unsigned(ACC_W-1 downto 0);
        variable new_sample_acc : unsigned(ACC_W-1 downto 0);
        variable sample         : unsigned(DATA_W-1 downto 0);
    begin
        if rst_n = '0' then
            samples          <= (others => (others => '0'));
            accumulator      <= (others => '0');
            write_pointer    <= 0;
            output_data_reg  <= (others => '0');
            output_valid_reg <= '0';
        elsif rising_edge(clk) then
            if input_accept = '1' then
                sample := unsigned(data_in);
                old_sample_acc := resize(samples(write_pointer), ACC_W);
                new_sample_acc := resize(sample, ACC_W);
                next_acc := accumulator - old_sample_acc + new_sample_acc;
                average_value := next_acc / TAPS;

                samples(write_pointer) <= sample;
                accumulator <= next_acc;
                output_data_reg <= std_logic_vector(resize(average_value, 16));
                output_valid_reg <= '1';

                if write_pointer = TAPS-1 then
                    write_pointer <= 0;
                else
                    write_pointer <= write_pointer + 1;
                end if;
            elsif output_consume = '1' then
                output_valid_reg <= '0';
            end if;
        end if;
    end process;

    data_out <= output_data_reg;
    valid_out <= output_valid_reg;
end architecture rtl;