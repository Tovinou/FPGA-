	Max10_embedded_sys u0 (
		.adc_fifo_0_status_level             (<connected-to-adc_fifo_0_status_level>),             //            adc_fifo_0_status.level
		.adc_fifo_0_status_empty             (<connected-to-adc_fifo_0_status_empty>),             //                             .empty
		.adc_fifo_0_status_full              (<connected-to-adc_fifo_0_status_full>),              //                             .full
		.adc_fifo_0_status_almost_full       (<connected-to-adc_fifo_0_status_almost_full>),       //                             .almost_full
		.adc_fifo_0_status_almost_empty      (<connected-to-adc_fifo_0_status_almost_empty>),      //                             .almost_empty
		.adc_reader_0_control_enable         (<connected-to-adc_reader_0_control_enable>),         //         adc_reader_0_control.enable
		.adc_reader_0_control_busy           (<connected-to-adc_reader_0_control_busy>),           //                             .busy
		.altpll_0_c2_clk                     (<connected-to-altpll_0_c2_clk>),                     //                  altpll_0_c2.clk
		.altpll_0_locked_conduit_export      (<connected-to-altpll_0_locked_conduit_export>),      //      altpll_0_locked_conduit.export
		.button_export                       (<connected-to-button_export>),                       //                       button.export
		.cap_conduit                         (<connected-to-cap_conduit>),                         //                          cap.conduit
		.clk_clk                             (<connected-to-clk_clk>),                             //                          clk.clk
		.ledr_export                         (<connected-to-ledr_export>),                         //                         ledr.export
		.modular_adc_0_adc_pll_locked_export (<connected-to-modular_adc_0_adc_pll_locked_export>), // modular_adc_0_adc_pll_locked.export
		.pwm_conduit                         (<connected-to-pwm_conduit>),                         //                          pwm.conduit
		.reset_reset_n                       (<connected-to-reset_reset_n>),                       //                        reset.reset_n
		.sdram_wire_addr                     (<connected-to-sdram_wire_addr>),                     //                   sdram_wire.addr
		.sdram_wire_ba                       (<connected-to-sdram_wire_ba>),                       //                             .ba
		.sdram_wire_cas_n                    (<connected-to-sdram_wire_cas_n>),                    //                             .cas_n
		.sdram_wire_cke                      (<connected-to-sdram_wire_cke>),                      //                             .cke
		.sdram_wire_cs_n                     (<connected-to-sdram_wire_cs_n>),                     //                             .cs_n
		.sdram_wire_dq                       (<connected-to-sdram_wire_dq>),                       //                             .dq
		.sdram_wire_dqm                      (<connected-to-sdram_wire_dqm>),                      //                             .dqm
		.sdram_wire_ras_n                    (<connected-to-sdram_wire_ras_n>),                    //                             .ras_n
		.sdram_wire_we_n                     (<connected-to-sdram_wire_we_n>)                      //                             .we_n
	);

