
module Max10_embedded_sys (
	adc_fifo_0_status_level,
	adc_fifo_0_status_empty,
	adc_fifo_0_status_full,
	adc_fifo_0_status_almost_full,
	adc_fifo_0_status_almost_empty,
	adc_reader_0_control_enable,
	adc_reader_0_control_busy,
	altpll_0_c2_clk,
	altpll_0_locked_conduit_export,
	button_export,
	cap_conduit,
	clk_clk,
	ledr_export,
	modular_adc_0_adc_pll_locked_export,
	pwm_conduit,
	reset_reset_n,
	sdram_wire_addr,
	sdram_wire_ba,
	sdram_wire_cas_n,
	sdram_wire_cke,
	sdram_wire_cs_n,
	sdram_wire_dq,
	sdram_wire_dqm,
	sdram_wire_ras_n,
	sdram_wire_we_n);	

	output	[31:0]	adc_fifo_0_status_level;
	output		adc_fifo_0_status_empty;
	output		adc_fifo_0_status_full;
	output		adc_fifo_0_status_almost_full;
	output		adc_fifo_0_status_almost_empty;
	input		adc_reader_0_control_enable;
	output		adc_reader_0_control_busy;
	output		altpll_0_c2_clk;
	output		altpll_0_locked_conduit_export;
	input	[1:0]	button_export;
	input		cap_conduit;
	input		clk_clk;
	output	[9:0]	ledr_export;
	input		modular_adc_0_adc_pll_locked_export;
	output		pwm_conduit;
	input		reset_reset_n;
	output	[12:0]	sdram_wire_addr;
	output	[1:0]	sdram_wire_ba;
	output		sdram_wire_cas_n;
	output		sdram_wire_cke;
	output		sdram_wire_cs_n;
	inout	[15:0]	sdram_wire_dq;
	output	[1:0]	sdram_wire_dqm;
	output		sdram_wire_ras_n;
	output		sdram_wire_we_n;
endmodule
