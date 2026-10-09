onerror {quit -code 1}
source "C:/Jensen/projects/fpga/live_stream/sys_ctrl/vunit_out/test_output/lib.tb_debounce_explicit.press_and_release_no_bounce_d96f0941ccdad6db617e5131d51353feff8187f8/modelsim/common.do"
set failed [vunit_load]
if {$failed} {quit -code 1}
set failed [vunit_run]
if {$failed} {quit -code 1}
quit -code 0
