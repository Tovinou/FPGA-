-- Pointing and Tracking Control Component for MAX10
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pointing_control is
    port (
        clk              : in  std_logic;
        rst_n            : in  std_logic;
        target_azimuth   : in  std_logic_vector(15 downto 0);
        target_elevation : in  std_logic_vector(8 downto 0);  -- 9 bits for MAX10 GPIO
        tracking_enable  : in  std_logic;
        feedback_lock    : in  std_logic;
        azimuth_out      : out std_logic_vector(15 downto 0);
        elevation_out    : out std_logic_vector(8 downto 0);  -- 9 bits for MAX10 GPIO
        pointing_stable  : out std_logic
    );
end pointing_control;

architecture rtl of pointing_control is
    signal current_azimuth   : signed(15 downto 0);
    signal current_elevation : signed(8 downto 0);   -- Reduced to 9 bits
    signal azimuth_error    : signed(16 downto 0);   -- 17 bits due to sign extension
    signal elevation_error  : signed(9 downto 0);    -- 10 bits due to sign extension
    
    -- PID controller parameters
    constant KP : signed(15 downto 0) := to_signed(256, 16);   -- Proportional gain
    constant KI : signed(15 downto 0) := to_signed(32, 16);    -- Integral gain
    constant KD : signed(15 downto 0) := to_signed(64, 16);    -- Derivative gain
    
    -- PID controller signals
    signal azimuth_integral   : signed(31 downto 0);
    signal elevation_integral : signed(31 downto 0);
    signal azimuth_derivative : signed(16 downto 0);
    signal elevation_derivative : signed(9 downto 0);
    signal prev_azimuth_error   : signed(16 downto 0);
    signal prev_elevation_error : signed(9 downto 0);
    
    -- Control outputs
    signal azimuth_control   : signed(31 downto 0);
    signal elevation_control : signed(31 downto 0);
    
    -- Stability detection
    signal stability_counter : integer range 0 to 1023;
    constant STABILITY_THRESHOLD : integer := 100;
    
    -- State machine for pointing control
    type pointing_state_t is (IDLE, COARSE_POINT, FINE_TRACK, LOCKED);
    signal pointing_state : pointing_state_t;
    
begin
    -- Main pointing control process
    pointing_proc: process(clk, rst_n)
        variable az_p_term, az_i_term, az_d_term : signed(31 downto 0);
        variable el_p_term, el_i_term, el_d_term : signed(31 downto 0);
        variable az_error_trunc : signed(15 downto 0);  -- Truncated to 16 bits
        variable el_error_trunc : signed(8 downto 0);   -- Truncated to 9 bits
        variable elevation_update : signed(8 downto 0); -- Explicit 9-bit update term
    begin
        if rst_n = '0' then
            current_azimuth <= (others => '0');
            current_elevation <= (others => '0');
            azimuth_error <= (others => '0');
            elevation_error <= (others => '0');
            azimuth_integral <= (others => '0');
            elevation_integral <= (others => '0');
            azimuth_derivative <= (others => '0');
            elevation_derivative <= (others => '0');
            prev_azimuth_error <= (others => '0');
            prev_elevation_error <= (others => '0');
            stability_counter <= 0;
            pointing_state <= IDLE;
            pointing_stable <= '0';
            
        elsif rising_edge(clk) then
            -- Calculate pointing errors
            azimuth_error <= signed('0' & target_azimuth) - current_azimuth;
            elevation_error <= signed('0' & target_elevation) - current_elevation;
            
            -- Truncate errors for PID calculations
            az_error_trunc := azimuth_error(15 downto 0);  -- Truncate to 16 bits
            el_error_trunc := elevation_error(8 downto 0); -- Truncate to 9 bits
            
            -- State machine for pointing control
            case pointing_state is
                when IDLE =>
                    if tracking_enable = '1' then
                        pointing_state <= COARSE_POINT;
                        stability_counter <= 0;
                        pointing_stable <= '0';
                    end if;
                
                when COARSE_POINT =>
                    -- Large step movements for initial pointing
                    if abs(azimuth_error) > 1000 or abs(elevation_error) > 100 then
                        if azimuth_error > 0 then
                            current_azimuth <= current_azimuth + 100;
                        else
                            current_azimuth <= current_azimuth - 100;
                        end if;
                        
                        if elevation_error > 0 then
                            current_elevation <= current_elevation + 10;  -- Smaller step for 9-bit range
                        else
                            current_elevation <= current_elevation - 10;
                        end if;
                    else
                        pointing_state <= FINE_TRACK;
                    end if;
                
                when FINE_TRACK =>
                    -- PID controller calculations
                    -- Proportional term
                    az_p_term := KP * az_error_trunc;  -- 16-bit * 16-bit = 32-bit
                    el_p_term := KP * resize(el_error_trunc, 16);  -- Resize to 16-bit for multiplication
                    
                    -- Integral term (with windup protection)
                    if abs(azimuth_integral) < 1000000 then
                        azimuth_integral <= azimuth_integral + resize(az_error_trunc, 32);
                    end if;
                    if abs(elevation_integral) < 1000000 then
                        elevation_integral <= elevation_integral + resize(el_error_trunc, 32);
                    end if;
                    
                    az_i_term := KI * azimuth_integral(23 downto 8);
                    el_i_term := KI * elevation_integral(23 downto 8);
                    
                    -- Derivative term
                    azimuth_derivative <= signed('0' & az_error_trunc) - prev_azimuth_error;  -- 17 bits
                    elevation_derivative <= signed('0' & el_error_trunc) - prev_elevation_error;  -- 10 bits
                    prev_azimuth_error <= signed('0' & az_error_trunc);
                    prev_elevation_error <= signed('0' & el_error_trunc);
                    
                    az_d_term := KD * resize(azimuth_derivative, 16);
                    el_d_term := KD * resize(elevation_derivative, 16);
                    
                    -- Combine PID terms
                    azimuth_control <= az_p_term + az_i_term + az_d_term;
                    elevation_control <= el_p_term + el_i_term + el_d_term;
                    
                    -- Apply control to current position
                    current_azimuth <= current_azimuth + azimuth_control(23 downto 8);
                    -- Explicit elevation update with clamping
                    elevation_update := signed(elevation_control(16 downto 8));  -- Correct 9-bit slice
                    if elevation_control(23 downto 8) >= 2**8 then
                        current_elevation <= to_signed(2**8 - 1, 9);  -- Clamp to +255
                    elsif elevation_control(23 downto 8) < -(2**8) then
                        current_elevation <= to_signed(-(2**8), 9);  -- Clamp to -256
                    else
                        current_elevation <= current_elevation + elevation_update;
                    end if;
                    
                    -- Check for stability
                    if abs(azimuth_error) < 50 and abs(elevation_error) < 10 then
                        stability_counter <= stability_counter + 1;
                        if stability_counter > STABILITY_THRESHOLD then
                            pointing_state <= LOCKED;
                            pointing_stable <= '1';
                        end if;
                    else
                        stability_counter <= 0;
                    end if;
                
                when LOCKED =>
                    -- Fine tracking with feedback
                    if feedback_lock = '1' then
                        -- Use feedback for precise tracking
                        current_azimuth <= current_azimuth + azimuth_control(23 downto 8);
                        -- Explicit elevation update with clamping
                        elevation_update := signed(elevation_control(16 downto 8));  -- Correct 9-bit slice
                        if elevation_control(23 downto 8) >= 2**8 then
                            current_elevation <= to_signed(2**8 - 1, 9);
                        elsif elevation_control(23 downto 8) < -(2**8) then
                            current_elevation <= to_signed(-(2**8), 9);
                        else
                            current_elevation <= current_elevation + elevation_update;
                        end if;
                    else
                        pointing_state <= FINE_TRACK;
                        pointing_stable <= '0';
                    end if;
                    
                    if tracking_enable = '0' then
                        pointing_state <= IDLE;
                        pointing_stable <= '0';
                    end if;
                
                when others =>
                    pointing_state <= IDLE;
            end case;
        end if;
    end process;

    -- Output assignments
    azimuth_out <= std_logic_vector(current_azimuth);
    elevation_out <= std_logic_vector(current_elevation);

end rtl;