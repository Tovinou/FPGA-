	component Max10_embedded_sys is
		port (
			adc_fifo_0_status_level             : out std_logic_vector(31 downto 0);                    -- level
			adc_fifo_0_status_empty             : out std_logic;                                        -- empty
			adc_fifo_0_status_full              : out std_logic;                                        -- full
			adc_fifo_0_status_almost_full       : out std_logic;                                        -- almost_full
			adc_fifo_0_status_almost_empty      : out std_logic;                                        -- almost_empty
			adc_reader_0_control_enable         : in  std_logic                     := 'X';             -- enable
			adc_reader_0_control_busy           : out std_logic;                                        -- busy
			altpll_0_locked_conduit_export      : out std_logic;                                        -- export
			button_export                       : in  std_logic_vector(1 downto 0)  := (others => 'X'); -- export
			cap_conduit                         : in  std_logic                     := 'X';             -- conduit
			clk_clk                             : in  std_logic                     := 'X';             -- clk
			ledr_export                         : out std_logic_vector(9 downto 0);                     -- export
			modular_adc_0_adc_pll_locked_export : in  std_logic                     := 'X';             -- export
			pwm_conduit                         : out std_logic;                                        -- conduit
			reset_reset_n                       : in  std_logic                     := 'X'              -- reset_n
		);
	end component Max10_embedded_sys;

	u0 : component Max10_embedded_sys
		port map (
			adc_fifo_0_status_level             => CONNECTED_TO_adc_fifo_0_status_level,             --            adc_fifo_0_status.level
			adc_fifo_0_status_empty             => CONNECTED_TO_adc_fifo_0_status_empty,             --                             .empty
			adc_fifo_0_status_full              => CONNECTED_TO_adc_fifo_0_status_full,              --                             .full
			adc_fifo_0_status_almost_full       => CONNECTED_TO_adc_fifo_0_status_almost_full,       --                             .almost_full
			adc_fifo_0_status_almost_empty      => CONNECTED_TO_adc_fifo_0_status_almost_empty,      --                             .almost_empty
			adc_reader_0_control_enable         => CONNECTED_TO_adc_reader_0_control_enable,         --         adc_reader_0_control.enable
			adc_reader_0_control_busy           => CONNECTED_TO_adc_reader_0_control_busy,           --                             .busy
			altpll_0_locked_conduit_export      => CONNECTED_TO_altpll_0_locked_conduit_export,      --      altpll_0_locked_conduit.export
			button_export                       => CONNECTED_TO_button_export,                       --                       button.export
			cap_conduit                         => CONNECTED_TO_cap_conduit,                         --                          cap.conduit
			clk_clk                             => CONNECTED_TO_clk_clk,                             --                          clk.clk
			ledr_export                         => CONNECTED_TO_ledr_export,                         --                         ledr.export
			modular_adc_0_adc_pll_locked_export => CONNECTED_TO_modular_adc_0_adc_pll_locked_export, -- modular_adc_0_adc_pll_locked.export
			pwm_conduit                         => CONNECTED_TO_pwm_conduit,                         --                          pwm.conduit
			reset_reset_n                       => CONNECTED_TO_reset_reset_n                        --                        reset.reset_n
		);

