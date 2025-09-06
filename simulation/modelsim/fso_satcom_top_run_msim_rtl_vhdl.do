transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vcom -93 -work work {C:/AGSTU/projects/fso_satcom/fso_satcom_top.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/error_correction_codec.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/frame_sync.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/optical_modulator.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/pointing_control.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/link_monitor.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/pll_clocks.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/debug_counters.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/deserializer.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/serializer.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/system_control_fsm.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/seven_segment_decoder.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/debouncer.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/synchronizer.vhd}
vcom -93 -work work {C:/AGSTU/projects/fso_satcom/test_data_generator.vhd}

vcom -93 -work work {C:/AGSTU/projects/fso_satcom/simulation/modelsim/fso_satcom_top.vht}

vsim -t 1ps -L altera -L lpm -L sgate -L altera_mf -L altera_lnsim -L fiftyfivenm -L rtl_work -L work -voptargs="+acc"  fso_satcom_top_vhd_tst

add wave *
view structure
view signals
run -all
