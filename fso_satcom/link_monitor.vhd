library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity link_monitor is
    port (
        clk              : in  std_logic;
        rst_n            : in  std_logic;
        rx_data          : in  std_logic;
        error_detected   : in  std_logic;
        frame_valid      : in  std_logic;
        link_quality     : out std_logic_vector(7 downto 0);
        bit_error_rate   : out std_logic_vector(15 downto 0);
        signal_strength  : out std_logic_vector(7 downto 0)
    );
end link_monitor;

architecture rtl of link_monitor is
    -- Counters for statistics
    signal bit_count          : unsigned(31 downto 0);
    signal error_count        : unsigned(31 downto 0);
    signal frame_count        : unsigned(15 downto 0);
    signal valid_frame_count  : unsigned(15 downto 0);
    
    -- Signal strength estimation
    signal rx_data_history    : std_logic_vector(31 downto 0);
    signal strength_estimate  : unsigned(7 downto 0);
    
    -- Moving average accumulators
    signal ber_accumulator    : unsigned(31 downto 0);
    signal quality_accumulator: unsigned(15 downto 0);
    signal sample_counter      : unsigned(7 downto 0);
    
    -- Update timing
    signal update_timer       : unsigned(15 downto 0);
    constant UPDATE_PERIOD    : integer := 10000; -- Update every 10k cycles
    
    -- Link quality calculation
    signal calculated_quality : unsigned(7 downto 0);
    signal calculated_ber     : unsigned(15 downto 0);
    
begin
    -- Main monitoring process
    monitor_proc: process(clk, rst_n)
        variable temp_ber : unsigned(47 downto 0);  -- Intermediate calc
        variable frame_success_rate : unsigned(15 downto 0);
        variable v_transition_count : unsigned(7 downto 0);
        variable temp_product : unsigned(127 downto 0); -- Widened to 128 bits
    begin
        if rst_n = '0' then
            bit_count          <= (others => '0');
            error_count        <= (others => '0');
            frame_count        <= (others => '0');
            valid_frame_count  <= (others => '0');
            rx_data_history    <= (others => '0');
            strength_estimate  <= (others => '0');
            ber_accumulator    <= (others => '0');
            quality_accumulator<= (others => '0');
            sample_counter     <= (others => '0');
            update_timer       <= (others => '0');
            calculated_quality <= (others => '0');
            calculated_ber     <= (others => '0');
        elsif rising_edge(clk) then
            -- Count bits and errors
            bit_count <= bit_count + 1;
            if error_detected = '1' then
                error_count <= error_count + 1;
            end if;
            
            -- Frame statistics
            if frame_valid = '1' then
                frame_count <= frame_count + 1;
                if error_detected = '0' then
                    valid_frame_count <= valid_frame_count + 1;
                end if;
            end if;
            
            -- Signal strength: transition density in history
            rx_data_history <= rx_data_history(30 downto 0) & rx_data;
            
            v_transition_count := (others => '0');
            for i in 0 to 30 loop
                if rx_data_history(i) /= rx_data_history(i+1) then
                    v_transition_count := v_transition_count + 1;
                end if;
            end loop;
            
            if v_transition_count > 20 then
                strength_estimate <= x"FF"; -- Strong
            elsif v_transition_count > 15 then
                strength_estimate <= x"C0"; -- Good
            elsif v_transition_count > 10 then
                strength_estimate <= x"80"; -- Medium
            elsif v_transition_count > 5 then
                strength_estimate <= x"40"; -- Weak
            else
                strength_estimate <= x"20"; -- Very weak
            end if;
            
            -- Update calculations periodically
            update_timer <= update_timer + 1;
            if update_timer = UPDATE_PERIOD then
                update_timer <= (others => '0');
                
                -- BER = (errors / total_bits) scaled
                if bit_count > 0 then
                    temp_product := resize(error_count, 64) * to_unsigned(65536, 64);
                    temp_ber := resize(temp_product(63 downto 0) / resize(bit_count, 64), 48);
                    calculated_ber <= temp_ber(15 downto 0);
                else
                    calculated_ber <= (others => '0');
                end if;
                
                -- Frame success rate
                if frame_count > 0 then
                    frame_success_rate := resize((valid_frame_count * 256) / frame_count, 16);
                else
                    frame_success_rate := (others => '0');
                end if;
                
                -- Link quality estimation
                if calculated_ber < 100 and frame_success_rate > 240 then
                    calculated_quality <= x"FF"; -- Excellent
                elsif calculated_ber < 500 and frame_success_rate > 200 then
                    calculated_quality <= x"C0"; -- Good
                elsif calculated_ber < 1000 and frame_success_rate > 150 then
                    calculated_quality <= x"80"; -- Fair
                elsif calculated_ber < 5000 and frame_success_rate > 100 then
                    calculated_quality <= x"40"; -- Poor
                else
                    calculated_quality <= x"20"; -- Very poor
                end if;
                
                -- Moving averages with proper resize
                ber_accumulator     <= ber_accumulator + resize(calculated_ber, ber_accumulator'length);
                quality_accumulator <= quality_accumulator + resize(calculated_quality, quality_accumulator'length);
                sample_counter      <= sample_counter + 1;
                
                -- Prevent overflow by halving counters
                if sample_counter = 255 then
                    bit_count           <= shift_right(bit_count, 1);
                    error_count         <= shift_right(error_count, 1);
                    frame_count         <= shift_right(frame_count, 1);
                    valid_frame_count   <= shift_right(valid_frame_count, 1);
                    ber_accumulator     <= shift_right(ber_accumulator, 1);
                    quality_accumulator <= shift_right(quality_accumulator, 1);
                    sample_counter      <= x"80";
                end if;
            end if;
        end if;
    end process;

    -- Outputs
    link_quality    <= std_logic_vector(quality_accumulator(15 downto 8)) when sample_counter > 0 else x"00";
    bit_error_rate  <= std_logic_vector(ber_accumulator(31 downto 16)) when sample_counter > 0 else x"0000";
    signal_strength <= std_logic_vector(strength_estimate);

end rtl;