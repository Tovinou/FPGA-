# Platform Designer component description for moving_average.vhd.
package require -exact qsys 16.1

set_module_property NAME moving_average
set_module_property VERSION 1.0
set_module_property DISPLAY_NAME "ADC Moving Average"
set_module_property DESCRIPTION "Backpressure-capable streaming moving-average filter"
set_module_property GROUP own_ip
set_module_property AUTHOR "Project"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL moving_average
add_fileset_file moving_average.vhd VHDL PATH ../../moving_average.vhd TOP_LEVEL_FILE

add_parameter TAPS INTEGER 16
set_parameter_property TAPS DEFAULT_VALUE 16
set_parameter_property TAPS DISPLAY_NAME "Number of taps"
set_parameter_property TAPS HDL_PARAMETER true

add_parameter DATA_W INTEGER 12
set_parameter_property DATA_W DEFAULT_VALUE 12
set_parameter_property DATA_W DISPLAY_NAME "ADC input width"
set_parameter_property DATA_W HDL_PARAMETER true

add_parameter COEF_W INTEGER 8
set_parameter_property COEF_W DEFAULT_VALUE 8
set_parameter_property COEF_W DISPLAY_NAME "Coefficient width"
set_parameter_property COEF_W HDL_PARAMETER true

add_parameter ACC_W INTEGER 20
set_parameter_property ACC_W DEFAULT_VALUE 20
set_parameter_property ACC_W DISPLAY_NAME "Accumulator width"
set_parameter_property ACC_W HDL_PARAMETER true

add_interface clock clock end
set_interface_property clock clockRate 0
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset rst_n reset_n Input 1

add_interface sample_sink avalon_streaming end
set_interface_property sample_sink associatedClock clock
set_interface_property sample_sink associatedReset reset
set_interface_property sample_sink dataBitsPerSymbol 12
set_interface_property sample_sink symbolsPerBeat 1
set_interface_property sample_sink readyLatency 0
add_interface_port sample_sink data_in data Input DATA_W
add_interface_port sample_sink valid_in valid Input 1
add_interface_port sample_sink ready_in ready Output 1

add_interface sample_source avalon_streaming start
set_interface_property sample_source associatedClock clock
set_interface_property sample_source associatedReset reset
set_interface_property sample_source dataBitsPerSymbol 16
set_interface_property sample_source symbolsPerBeat 1
set_interface_property sample_source readyLatency 0
add_interface_port sample_source data_out data Output 16
add_interface_port sample_source valid_out valid Output 1
add_interface_port sample_source ready_out ready Input 1
