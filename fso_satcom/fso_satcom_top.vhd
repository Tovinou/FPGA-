-- Free Space Optical Satellite Communication System
-- Top-level FPGA design for satellite optical communication
-- Author: FPGA Engineer Komlan Tovinou
-- Adapted for Intel MAX10 DE10-Lite FPGA Board
-- Date: 2025-08-30
-- Target: DE10-Lite with 50MHz onboard oscillator

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fso_satcom_top is
    generic (
        DATA_WIDTH     : integer := 32;
        FIFO_DEPTH     : integer := 512;
        FRAME_SIZE     : integer := 1024;
        LASER_FREQ_KHZ : integer := 1000;
        SYSTEM_CLK_MHZ : integer := 50
    );
    port (
        MAX10_CLK1_50  : in  std_logic;
        KEY            : in  std_logic_vector(1 downto 0);
        SW             : in  std_logic_vector(9 downto 0);
        LEDR           : out std_logic_vector(9 downto 0);
        HEX0           : out std_logic_vector(6 downto 0);
        HEX1           : out std_logic_vector(6 downto 0);
        HEX2           : out std_logic_vector(6 downto 0);
        HEX3           : out std_logic_vector(6 downto 0);
        HEX4           : out std_logic_vector(6 downto 0);
        HEX5           : out std_logic_vector(6 downto 0);
        GPIO_IN        : in  std_logic;  -- For optical_rx_data (GPIO[1])
        GPIO_OUT       : out std_logic_vector(34 downto 0)  -- For GPIO[0], GPIO[2:35]
    );
end fso_satcom_top;

architecture rtl of fso_satcom_top is    
    signal clk_50mhz        : std_logic;
    signal rst_n            : std_logic;
    signal pll_locked       : std_logic;
    signal optical_tx_data  : std_logic;
    signal optical_rx_data  : std_logic;
    signal laser_enable     : std_logic;
    signal laser_power_ctrl : std_logic_vector(7 downto 0);
    signal azimuth_angle    : std_logic_vector(15 downto 0);
    signal elevation_angle  : std_logic_vector(8 downto 0);
    signal tx_data_in       : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal tx_data_valid    : std_logic;
    signal rx_data_out      : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal rx_data_valid    : std_logic;
    signal rx_deserialized_valid : std_logic;
    signal link_quality     : std_logic_vector(7 downto 0);
    signal bit_error_rate   : std_logic_vector(15 downto 0);
    signal debug_signals    : std_logic_vector(31 downto 0);
    signal display_mode     : std_logic_vector(2 downto 0);
    signal clk_25mhz        : std_logic;
    signal clk_1mhz         : std_logic;
    signal key_debounced    : std_logic_vector(1 downto 0);
    signal sync_out         : std_logic_vector(1 downto 0);
    signal hex_enable       : std_logic;
    signal tx_encoded_data  : std_logic_vector(39 downto 0);
    signal tx_encoded_valid : std_logic;
    signal tx_serial_data   : std_logic;
    signal rx_frame_sync    : std_logic;
    signal rx_frame_valid   : std_logic;
    signal rx_decoded_data  : std_logic_vector(39 downto 0);
    signal rx_frame_data_valid : std_logic;
    signal rx_error_detected: std_logic;
    signal rx_error_corrected: std_logic;
    signal laser_power_level: std_logic_vector(7 downto 0);
    signal pointing_stable  : std_logic;
    signal system_ready     : std_logic;
    signal link_established : std_logic;
    type system_state_t is (IDLE, POINTING, LINK_SETUP, TRANSMITTING, ERROR_STATE);
    signal system_state : system_state_t;

    component error_correction_codec is
        generic (
            DATA_WIDTH  : integer := 32;
            PARITY_BITS : integer := 8
        );
        port (
            clk             : in  std_logic;
            rst_n           : in  std_logic;
            encode_mode     : in  std_logic;
            data_in         : in  std_logic_vector(DATA_WIDTH + PARITY_BITS - 1 downto 0);
            data_in_valid   : in  std_logic;
            data_out        : out std_logic_vector(DATA_WIDTH + PARITY_BITS - 1 downto 0);
            data_out_valid  : out std_logic;
            error_detected  : out std_logic;
            error_corrected : out std_logic
        );
    end component;

    component frame_sync is
        generic (
            FRAME_SIZE : integer := 1024
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
    end component;

    component optical_modulator is
        generic (
            LASER_FREQ_KHZ : integer := 1000
        );
        port (
            clk              : in  std_logic;
            rst_n            : in  std_logic;
            enable           : in  std_logic;
            data_in          : in  std_logic;
            power_level      : in  std_logic_vector(7 downto 0);
            optical_out      : out std_logic;
            laser_drive      : out std_logic;
            power_control    : out std_logic_vector(7 downto 0)
        );
    end component;

    component pointing_control is
        port (
            clk              : in  std_logic;
            rst_n            : in  std_logic;
            target_azimuth   : in  std_logic_vector(15 downto 0);
            target_elevation : in  std_logic_vector(8 downto 0);
            tracking_enable  : in  std_logic;
            feedback_lock    : in  std_logic;
            azimuth_out      : out std_logic_vector(15 downto 0);
            elevation_out    : out std_logic_vector(8 downto 0);
            pointing_stable  : out std_logic
        );
    end component;

    component link_monitor is
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
    end component;

    component pll_clocks is
        port (
            clk_in_50mhz     : in  std_logic;
            rst_n            : in  std_logic;
            clk_25mhz        : out std_logic;
            clk_1mhz         : out std_logic;
            locked           : out std_logic
        );
    end component;

    component debug_counters is
        port (
            clk       : in  std_logic;
            rst_n     : in  std_logic;
            tx_event  : in  std_logic;
            rx_event  : in  std_logic;
            tx_count  : out std_logic_vector(15 downto 0);
            rx_count  : out std_logic_vector(15 downto 0)
        );
    end component;

    component deserializer is
        generic (
            WIDTH : integer := 40
        );
        port (
            clk       : in  std_logic;
            rst_n     : in  std_logic;
            serial_in : in  std_logic;
            valid_in  : in  std_logic;
            data_out  : out std_logic_vector(WIDTH-1 downto 0);
            valid_out : out std_logic
        );
    end component;

    component serializer is 
        generic (
            WIDTH : integer := 40
        );
        port (
            clk      : in  std_logic;
            rst_n    : in  std_logic;
            data_in  : in  std_logic_vector(WIDTH-1 downto 0);
            valid_in : in  std_logic;
            data_out : out std_logic
        );
    end component;

    component system_control_fsm is
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
    end component;

    component seven_segment_decoder is
        generic (
            SLICE_OFFSET : integer := 0
        );
        port (
            display_mode     : in  std_logic_vector(2 downto 0);
            rx_data_out      : in  std_logic_vector(23 downto 0);
            link_quality     : in  std_logic_vector(7 downto 0);
            bit_error_rate   : in  std_logic_vector(15 downto 0);
            rx_error_corrected : in  std_logic;
            debug_signals    : in  std_logic_vector(23 downto 0);
            enable           : in  std_logic;
            segments         : out std_logic_vector(6 downto 0)
        );
    end component;

    component debouncer is
        generic (
            DEBOUNCE_LIMIT : integer := 1000000
        );
        port (
            clk          : in  std_logic;
            rst_n        : in  std_logic;
            key_in       : in  std_logic_vector(1 downto 0);
            key_debounced: out std_logic_vector(1 downto 0)
        );
    end component;

    component synchronizer is
        port (
            clk      : in  std_logic;
            rst_n    : in  std_logic;
            data_in  : in  std_logic_vector(1 downto 0);
            data_out : out std_logic_vector(1 downto 0)
        );
    end component;

    component test_data_generator is
        generic (
            DATA_WIDTH : integer := 32
        );
        port (
            clk        : in  std_logic;
            rst_n      : in  std_logic;
            data_valid : in  std_logic;
            data_out   : out std_logic_vector(DATA_WIDTH-1 downto 0)
        );
    end component;

begin
    -- Signal assignments
    clk_50mhz          <= MAX10_CLK1_50;
    rst_n              <= SW(9);
    laser_power_level  <= SW(7 downto 0) when SW(8) = '1' else x"80";
    display_mode       <= SW(2 downto 0);
    tx_data_valid      <= SW(3);
    optical_rx_data    <= GPIO_IN;
    GPIO_OUT(0)        <= optical_tx_data;
    GPIO_OUT(1)        <= laser_enable;
    GPIO_OUT(9 downto 2) <= laser_power_ctrl;
    GPIO_OUT(25 downto 10) <= azimuth_angle;
    GPIO_OUT(34 downto 26) <= elevation_angle;
    hex_enable         <= system_ready;

    -- Component instantiations
    debouncer_inst: debouncer
    generic map (
        DEBOUNCE_LIMIT => 1000000
    )
    port map (
        clk           => clk_50mhz,
        rst_n         => rst_n,
        key_in        => KEY,
        key_debounced => key_debounced
    );

    sync_inst: synchronizer
    port map (
        clk      => clk_25mhz,
        rst_n    => rst_n,
        data_in  => key_debounced,
        data_out => sync_out
    );

    test_data_inst: test_data_generator
    generic map (
        DATA_WIDTH => DATA_WIDTH
    )
    port map (
        clk        => clk_25mhz,
        rst_n      => rst_n,
        data_valid => tx_data_valid,
        data_out   => tx_data_in
    );

    pll_inst: pll_clocks
    port map (
        clk_in_50mhz   => clk_50mhz,
        rst_n          => rst_n,
        clk_25mhz      => clk_25mhz,
        clk_1mhz       => clk_1mhz,
        locked         => pll_locked
    );

    tx_ecc_inst: error_correction_codec
    generic map (
        DATA_WIDTH      => DATA_WIDTH,
        PARITY_BITS     => 8
    )
    port map (
        clk             => clk_25mhz,
        rst_n           => rst_n,
        encode_mode     => '1',
        data_in         => tx_data_in & "00000000",
        data_in_valid   => tx_data_valid,
        data_out        => tx_encoded_data,
        data_out_valid  => tx_encoded_valid,
        error_detected  => open,
        error_corrected => open
    );

    rx_ecc_inst: error_correction_codec
    generic map (
        DATA_WIDTH      => DATA_WIDTH,
        PARITY_BITS     => 8
    )
    port map (
        clk             => clk_25mhz,
        rst_n           => rst_n,
        encode_mode     => '0',
        data_in         => rx_decoded_data,
        data_in_valid   => rx_deserialized_valid,
        data_out        => open,
        data_out_valid  => rx_data_valid,
        error_detected  => rx_error_detected,
        error_corrected => rx_error_corrected
    );

    frame_sync_inst: frame_sync
    generic map (
        FRAME_SIZE       => FRAME_SIZE
    )
    port map (
        clk              => clk_25mhz,
        rst_n            => rst_n,
        serial_data_in   => optical_rx_data,
        frame_sync_out   => rx_frame_sync,
        frame_valid      => rx_frame_valid,
        frame_data_out   => open,
        frame_data_valid => rx_frame_data_valid
    );

    optical_mod_inst: optical_modulator
    generic map (
        LASER_FREQ_KHZ => LASER_FREQ_KHZ
    )
    port map (
        clk           => clk_1mhz,
        rst_n         => rst_n,
        enable        => sync_out(1) and link_established,
        data_in       => tx_serial_data,
        power_level   => laser_power_level,
        optical_out   => optical_tx_data,
        laser_drive   => laser_enable,
        power_control => laser_power_ctrl
    );

    pointing_inst: pointing_control
    port map (
        clk              => clk_50mhz,
        rst_n            => rst_n,
        target_azimuth   => x"8000",
        target_elevation => "100000000",
        tracking_enable  => sync_out(1),
        feedback_lock    => sync_out(0),
        azimuth_out      => azimuth_angle,
        elevation_out    => elevation_angle,
        pointing_stable  => pointing_stable
    );

    monitor_inst: link_monitor
    port map (
        clk              => clk_25mhz,
        rst_n            => rst_n,
        rx_data          => optical_rx_data,
        error_detected   => rx_error_detected,
        frame_valid      => rx_frame_valid,
        link_quality     => link_quality,
        bit_error_rate   => bit_error_rate,
        signal_strength  => open
    );

    fsm_inst: system_control_fsm
    port map (
        clk              => clk_25mhz,
        rst_n            => rst_n,
        system_enable    => sync_out(1),
        pll_locked       => pll_locked,
        pointing_stable  => pointing_stable,
        tracking_lock    => sync_out(0),
        rx_frame_sync    => rx_frame_sync,
        link_quality     => link_quality,
        system_ready     => system_ready,
        link_established => link_established,
        tx_data_ready    => open
    );

    serializer_inst: serializer
    generic map (WIDTH => 40)
    port map (
        clk      => clk_1mhz,
        rst_n    => rst_n,
        data_in  => tx_encoded_data,
        valid_in => tx_encoded_valid,
        data_out => tx_serial_data
    );

    deserializer_inst: deserializer
    generic map (WIDTH => 40)
    port map (
        clk       => clk_1mhz,
        rst_n     => rst_n,
        serial_in => optical_rx_data,
        valid_in  => rx_frame_data_valid,
        data_out  => rx_decoded_data,
        valid_out => rx_deserialized_valid
    );

    debug_inst: debug_counters
    port map (
        clk      => clk_25mhz,
        rst_n    => rst_n,
        tx_event => tx_encoded_valid,
        rx_event => rx_data_valid,
        tx_count => debug_signals(31 downto 16),
        rx_count => debug_signals(15 downto 0)
    );

    rx_data_out <= rx_decoded_data(31 downto 0);

    -- LEDR assignment process to ensure synthesis-friendly logic
    process(clk_25mhz, rst_n)
    begin
        if rst_n = '0' then
            LEDR <= (others => '0');
        elsif rising_edge(clk_25mhz) then
            case display_mode is
                when "001" =>
                    LEDR <= link_quality(7 downto 0) & "00";
                when "010" =>
                    LEDR <= bit_error_rate(9 downto 0);
                when "011" =>
                    LEDR <= rx_data_out(9 downto 0);
                when "100" =>
                    LEDR <= "000000000" & rx_error_corrected;
                when others =>
                    LEDR <= debug_signals(9 downto 0);
            end case;
        end if;
    end process;

    hex0_inst: seven_segment_decoder
    generic map (
        SLICE_OFFSET => 0
    )
    port map (
        display_mode     => display_mode,
        rx_data_out      => rx_data_out(23 downto 0),
        link_quality     => link_quality,
        bit_error_rate   => bit_error_rate,
        rx_error_corrected => rx_error_corrected,
        debug_signals    => debug_signals(23 downto 0),
        enable           => hex_enable,
        segments         => HEX0
    );

    hex1_inst: seven_segment_decoder
    generic map (
        SLICE_OFFSET => 4
    )
    port map (
        display_mode     => display_mode,
        rx_data_out      => rx_data_out(23 downto 0),
        link_quality     => link_quality,
        bit_error_rate   => bit_error_rate,
        rx_error_corrected => rx_error_corrected,
        debug_signals    => debug_signals(23 downto 0),
        enable           => hex_enable,
        segments         => HEX1
    );

    hex2_inst: seven_segment_decoder
    generic map (
        SLICE_OFFSET => 8
    )
    port map (
        display_mode     => display_mode,
        rx_data_out      => rx_data_out(23 downto 0),
        link_quality     => link_quality,
        bit_error_rate   => bit_error_rate,
        rx_error_corrected => rx_error_corrected,
        debug_signals    => debug_signals(23 downto 0),
        enable           => hex_enable,
        segments         => HEX2
    );

    hex3_inst: seven_segment_decoder
    generic map (
        SLICE_OFFSET => 12
    )
    port map (
        display_mode     => display_mode,
        rx_data_out      => rx_data_out(23 downto 0),
        link_quality     => link_quality,
        bit_error_rate   => bit_error_rate,
        rx_error_corrected => rx_error_corrected,
        debug_signals    => debug_signals(23 downto 0),
        enable           => hex_enable,
        segments         => HEX3
    );

    hex4_inst: seven_segment_decoder
    generic map (
        SLICE_OFFSET => 16
    )
    port map (
        display_mode     => display_mode,
        rx_data_out      => rx_data_out(23 downto 0),
        link_quality     => link_quality,
        bit_error_rate   => bit_error_rate,
        rx_error_corrected => rx_error_corrected,
        debug_signals    => debug_signals(23 downto 0),
        enable           => hex_enable,
        segments         => HEX4
    );

    hex5_inst: seven_segment_decoder
    generic map (
        SLICE_OFFSET => 20
    )
    port map (
        display_mode     => display_mode,
        rx_data_out      => rx_data_out(23 downto 0),
        link_quality     => link_quality,
        bit_error_rate   => bit_error_rate,
        rx_error_corrected => rx_error_corrected,
        debug_signals    => debug_signals(23 downto 0),
        enable           => hex_enable,
        segments         => HEX5
    );

end rtl;