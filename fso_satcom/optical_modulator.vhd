library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity optical_modulator is
    generic (
        LASER_FREQ_KHZ : integer := 1000  -- 1MHz for MAX10
    );
    port (
        clk           : in  std_logic;
        rst_n         : in  std_logic;
        enable        : in  std_logic;
        data_in       : in  std_logic;
        power_level   : in  std_logic_vector(7 downto 0);
        optical_out   : out std_logic;
        laser_drive   : out std_logic;
        power_control : out std_logic_vector(7 downto 0)
    );
end optical_modulator;

architecture rtl of optical_modulator is
    signal pwm_counter : unsigned(7 downto 0);
    signal laser_intensity : std_logic;
    signal data_sync : std_logic_vector(2 downto 0);
    
    -- State machine for modulation control
    type mod_state_t is (IDLE, PREAMBLE, DATA_TX, POSTAMBLE);
    signal mod_state : mod_state_t;
    signal preamble_counter : integer range 0 to 15;
    
begin

    -- Data synchronization
    data_sync_proc: process(clk, rst_n)
    begin
        if rst_n = '0' then
            data_sync <= (others => '0');
        elsif rising_edge(clk) then
            data_sync <= data_sync(1 downto 0) & data_in;
        end if;
    end process;

    -- PWM generation for laser power control (optimized for MAX10)
    pwm_proc: process(clk, rst_n)
    begin
        if rst_n = '0' then
            pwm_counter <= (others => '0');
            laser_intensity <= '0';
        elsif rising_edge(clk) then
            pwm_counter <= pwm_counter + 1;
            if pwm_counter < unsigned(power_level) then
                laser_intensity <= '1';
            else
                laser_intensity <= '0';
            end if;
        end if;
    end process;

    -- Fixed modulation state machine for MAX10
    modulation_control: process(clk, rst_n)
    begin
        if rst_n = '0' then
            mod_state <= IDLE;
            preamble_counter <= 0;
            optical_out <= '0';
            laser_drive <= '0';
        elsif rising_edge(clk) then
            case mod_state is
                when IDLE =>
                    laser_drive <= '0';
                    optical_out <= '0';
                    if enable = '1' then
                        mod_state <= PREAMBLE;
                        preamble_counter <= 0;
                    end if;
                
                when PREAMBLE =>
                    laser_drive <= laser_intensity;
                    -- Fixed: Send alternating pattern for clock recovery
                    if (preamble_counter mod 2) = 0 then
                        optical_out <= '1';
                    else
                        optical_out <= '0';
                    end if;
                    preamble_counter <= preamble_counter + 1;
                    if preamble_counter = 15 then
                        mod_state <= DATA_TX;
                    end if;
                
                when DATA_TX =>
                    laser_drive <= laser_intensity;
                    optical_out <= data_sync(2) and laser_intensity;
                    if enable = '0' then
                        mod_state <= POSTAMBLE;
                        preamble_counter <= 0;
                    end if;
                
                when POSTAMBLE =>
                    laser_drive <= laser_intensity;
                    optical_out <= '0';
                    preamble_counter <= preamble_counter + 1;
                    if preamble_counter = 7 then
                        mod_state <= IDLE;
                    end if;
                
                when others =>
                    mod_state <= IDLE;
            end case;
        end if;
    end process;

    -- Output power control
    power_control <= power_level when enable = '1' else x"00";

end rtl;