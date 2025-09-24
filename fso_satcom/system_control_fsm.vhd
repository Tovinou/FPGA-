library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity system_control_fsm is
    port (
        clk              : in  std_logic;
        rst_n            : in  std_logic;
        system_enable    : in  std_logic;
        pll_locked       : in  std_logic;
        pointing_stable  : in  std_logic;
        tracking_lock    : in  std_logic;
        rx_frame_sync    : in  std_logic;
        link_quality     : in  std_logic_vector(7 downto 0);

        system_ready     : out std_logic;
        link_established : out std_logic;
        tx_data_ready    : out std_logic
    );
end system_control_fsm;

architecture rtl of system_control_fsm is
    type system_state_t is (IDLE, POINTING, LINK_SETUP, TRANSMITTING, ERROR_STATE);
    signal state : system_state_t := IDLE;
begin
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            state <= IDLE;
            system_ready <= '0';
            link_established <= '0';
            tx_data_ready <= '0';
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    system_ready <= '0';
                    link_established <= '0';
                    tx_data_ready <= '0';
                    if system_enable = '1' and pll_locked = '1' then
                        state <= POINTING;
                        system_ready <= '1';
                    end if;

                when POINTING =>
                    if pointing_stable = '1' and tracking_lock = '1' then
                        state <= LINK_SETUP;
                    end if;

                when LINK_SETUP =>
                    if rx_frame_sync = '1' then
                        link_established <= '1';
                        tx_data_ready <= '1';
                        state <= TRANSMITTING;
                    end if;

                when TRANSMITTING =>
                    if unsigned(link_quality) < x"40" then
                        link_established <= '0';
                        state <= ERROR_STATE;
                    elsif system_enable = '0' then
                        link_established <= '0';
                        tx_data_ready <= '0';
                        state <= IDLE;
                    end if;

                when ERROR_STATE =>
                    if unsigned(link_quality) > x"80" then
                        link_established <= '1';
                        state <= TRANSMITTING;
                    else
                        link_established <= '0';
                        state <= POINTING;
                    end if;
            end case;
        end if;
    end process;
end rtl;
