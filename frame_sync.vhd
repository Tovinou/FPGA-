-- Frame Synchronization Component
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity frame_sync is
    generic (
        FRAME_SIZE : integer := 2048
    );
    port (
        clk              : in  std_logic;
        rst_n            : in  std_logic;
        serial_data_in   : in  std_logic;
        frame_sync_out   : out std_logic;
        frame_valid      : out std_logic;
        frame_data_out   : out std_logic_vector(7 downto 0);
        frame_data_valid : out std_logic
    );
end frame_sync;

architecture rtl of frame_sync is
    constant SYNC_PATTERN : std_logic_vector(31 downto 0) := x"DEADBEEF";
    signal shift_reg : std_logic_vector(31 downto 0);
    signal sync_found : std_logic;
    signal bit_counter : integer range 0 to FRAME_SIZE-1;
    signal byte_counter : integer range 0 to 7;
    signal frame_buffer : std_logic_vector(7 downto 0);
    
begin
    
    sync_process: process(clk, rst_n)
    begin
        if rst_n = '0' then
            shift_reg <= (others => '0');
            sync_found <= '0';
            frame_sync_out <= '0';
            bit_counter <= 0;
            byte_counter <= 0;
            frame_buffer <= (others => '0');
            frame_data_out <= (others => '0');
            frame_data_valid <= '0';
            frame_valid <= '0';
            
        elsif rising_edge(clk) then
            -- Shift in new bit
            shift_reg <= shift_reg(30 downto 0) & serial_data_in;
            
            -- Check for sync pattern
            if shift_reg = SYNC_PATTERN then
                sync_found <= '1';
                frame_sync_out <= '1';
                bit_counter <= 0;
                byte_counter <= 0;
            else
                frame_sync_out <= '0';
            end if;
            
            -- Process frame data after sync
            if sync_found = '1' then
                frame_buffer <= frame_buffer(6 downto 0) & serial_data_in;
                byte_counter <= byte_counter + 1;
                
                if byte_counter = 7 then
                    frame_data_out <= frame_buffer(6 downto 0) & serial_data_in;
                    frame_data_valid <= '1';
                    byte_counter <= 0;
                    bit_counter <= bit_counter + 8;
                else
                    frame_data_valid <= '0';
                end if;
                
                -- Check for end of frame
                if bit_counter >= FRAME_SIZE-8 then
                    sync_found <= '0';
                    frame_valid <= '1';
                else
                    frame_valid <= '0';
                end if;
            end if;
        end if;
    end process;

end rtl;