# Platform Designer component description for the ADC sample-store reader.
package require -exact qsys 16.1

set_module_property NAME adc_reader
set_module_property VERSION 1.0
set_module_property DISPLAY_NAME "ADC Sample Reader"
set_module_property DESCRIPTION "Reads Modular ADC sample-store slots and emits CH0 Avalon-ST samples"
set_module_property GROUP own_ip
set_module_property AUTHOR "Project"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL adc_reader
add_fileset_file adc_reader.vhd VHDL PATH HDL/adc_reader.vhd TOP_LEVEL_FILE

add_parameter SAMPLE_SLOTS INTEGER 64
set_parameter_property SAMPLE_SLOTS DEFAULT_VALUE 64
set_parameter_property SAMPLE_SLOTS DISPLAY_NAME "Sample-store slots"
set_parameter_property SAMPLE_SLOTS HDL_PARAMETER true

add_interface clock clock end
set_interface_property clock clockRate 0
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset_n reset_n Input 1

add_interface control conduit end
set_interface_property control associatedClock clock
set_interface_property control associatedReset reset
add_interface_port control enable enable Input 1
add_interface_port control busy busy Output 1

add_interface adc_master avalon master
set_interface_property adc_master addressUnits WORDS
set_interface_property adc_master associatedClock clock
set_interface_property adc_master associatedReset reset
set_interface_property adc_master bitsPerSymbol 8
set_interface_property adc_master readLatency 0
set_interface_property adc_master timingUnits Cycles
add_interface_port adc_master adc_address address Output 7
add_interface_port adc_master adc_read read Output 1
add_interface_port adc_master adc_write write Output 1
add_interface_port adc_master adc_writedata writedata Output 32
add_interface_port adc_master adc_readdata readdata Input 32
add_interface_port adc_master adc_waitrequest waitrequest Input 1

add_interface sample_source avalon_streaming start
set_interface_property sample_source associatedClock clock
set_interface_property sample_source associatedReset reset
set_interface_property sample_source dataBitsPerSymbol 12
set_interface_property sample_source symbolsPerBeat 1
set_interface_property sample_source readyLatency 0
add_interface_port sample_source sample_data data Output 12
add_interface_port sample_source sample_valid valid Output 1
add_interface_port sample_source sample_ready ready Input 1
