library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.env.all;

entity ssi_master_tb is
end entity ssi_master_tb;

architecture tb of ssi_master_tb is
    constant CLK_FREQ_HZ : positive := 50_000_000;
    constant SSI_CLK_HZ  : positive := 5_000_000;
    constant DATA_BITS   : positive := 8;

    constant CLK_PERIOD  : time := 20 ns;

    signal clk      : std_logic := '0';
    signal rst_n    : std_logic := '0';
    signal start    : std_logic := '0';
    signal busy     : std_logic;
    signal valid    : std_logic;
    signal position : std_logic_vector(DATA_BITS - 1 downto 0);
    signal ssi_clk  : std_logic;
    signal ssi_data : std_logic := '1';

    procedure pulse_start(signal clk_i : in std_logic; signal start_o : out std_logic) is
    begin
        start_o <= '1';
        wait until rising_edge(clk_i);
        start_o <= '0';
    end procedure;

    procedure drive_frame(
        signal clk_i      : in std_logic;
        signal start_o    : out std_logic;
        signal ssi_clk_i  : in std_logic;
        signal busy_i     : in std_logic;
        signal valid_i    : in std_logic;
        signal ssi_data_o : out std_logic;
        signal position_i : in std_logic_vector(DATA_BITS - 1 downto 0);
        constant bits     : in std_logic_vector(DATA_BITS - 1 downto 0)
    ) is
    begin
        pulse_start(clk_i, start_o);

        wait until busy_i = '1';

        wait until ssi_clk_i = '0';
        ssi_data_o <= bits(DATA_BITS - 1);

        for i in DATA_BITS - 2 downto 0 loop
            wait until (ssi_clk_i'event and ssi_clk_i = '0');
            ssi_data_o <= bits(i);
        end loop;

        wait until valid_i = '1';
        assert position_i = bits
            report "Captured position mismatch. Expected=" &
                   integer'image(to_integer(unsigned(bits))) &
                   " Got=" &
                   integer'image(to_integer(unsigned(position_i)))
            severity failure;

        ssi_data_o <= '1';

        wait until busy_i = '0';
        assert ssi_clk_i = '1'
            report "ssi_clk is not high while idle"
            severity failure;
    end procedure;
begin
    clk <= not clk after CLK_PERIOD / 2;

    uut : entity work.ssi_master
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            SSI_CLK_HZ  => SSI_CLK_HZ,
            DATA_BITS   => DATA_BITS
        )
        port map (
            clk      => clk,
            rst_n    => rst_n,
            start    => start,
            busy     => busy,
            valid    => valid,
            position => position,
            ssi_clk  => ssi_clk,
            ssi_data => ssi_data
        );

    p_stim : process
        constant frame1 : std_logic_vector(DATA_BITS - 1 downto 0) := x"A5";
        constant frame2 : std_logic_vector(DATA_BITS - 1 downto 0) := x"3C";
    begin
        rst_n <= '0';
        wait for 10 * CLK_PERIOD;
        rst_n <= '1';
        wait for 10 * CLK_PERIOD;

        drive_frame(clk, start, ssi_clk, busy, valid, ssi_data, position, frame1);
        drive_frame(clk, start, ssi_clk, busy, valid, ssi_data, position, frame2);

        stop;
        wait;
    end process;
end architecture tb;
