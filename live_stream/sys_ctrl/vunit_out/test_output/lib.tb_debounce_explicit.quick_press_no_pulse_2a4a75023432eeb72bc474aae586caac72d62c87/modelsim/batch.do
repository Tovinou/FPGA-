onerror {quit -code 1}
source "C:/Jensen/projects/fpga/live_stream/sys_ctrl/vunit_out/test_output/lib.tb_debounce_explicit.quick_press_no_pulse_2a4a75023432eeb72bc474aae586caac72d62c87/modelsim/common.do"
set failed [vunit_load]
if {$failed} {quit -code 1}
set failed [vunit_run]
if {$failed} {quit -code 1}
quit -code 0
