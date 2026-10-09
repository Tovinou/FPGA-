onerror {quit -code 1}
source "C:/Jensen/projects/fpga/live_stream/sys_ctrl/vunit_out/test_output/lib.tb_debounce_explicit.bounce_then_press_6ac2807c6efc5588dca28576fac8d68e737fd9f2/modelsim/common.do"
set failed [vunit_load]
if {$failed} {quit -code 1}
set failed [vunit_run]
if {$failed} {quit -code 1}
quit -code 0
