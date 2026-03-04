-------------------------------------------------------------------------------
-- Module 1: Button Debouncer
-------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.ALL;

entity debounce_button is
generic (
    slow_clk_nb_cycles : integer := 249999
);
port (
    clk : in std_logic;
    reset : in std_logic;
    button : in std_logic;
    debounce_button : out std_logic
);
end debounce_button;

architecture rtl of debounce_button is
    signal counter : integer range 0 to slow_clk_nb_cycles := 0;
    signal slow_clock_enable : std_logic;
    signal button_r0 : std_logic := '0';
    signal button_r1 : std_logic := '0';
    signal button_r2 : std_logic := '0';
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                counter <= 0;
            else
                if counter >= slow_clk_nb_cycles then
                    counter <= 0;
                else
                    counter <= counter + 1;
                end if;
            end if;
        end if;
    end process;

    slow_clock_enable <= '1' when counter = slow_clk_nb_cycles else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            if slow_clock_enable = '1' then
                button_r0 <= button;
                button_r1 <= button_r0;
                button_r2 <= button_r1;
            end if;
        end if;
    end process;

    debounce_button <= button_r1 and not(button_r2);
end rtl;