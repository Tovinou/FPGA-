# Platform Designer component description for the ADC sample FIFO.
package require -exact qsys 16.1

set_module_property NAME adc_fifo
set_module_property VERSION 1.0
set_module_property DISPLAY_NAME "ADC Sample FIFO"
set_module_property DESCRIPTION "Avalon-ST input and Avalon-MM sample FIFO for ADC processing"
set_module_property GROUP own_ip
set_module_property AUTHOR "Project"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true
set_module_property OPAQUE_ADDRESS_MAP true

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL adc_fifo
add_fileset_file fifo.vhd VHDL PATH HDL/fifo.vhd TOP_LEVEL_FILE

add_parameter DATA_WIDTH INTEGER 16
set_parameter_property DATA_WIDTH DEFAULT_VALUE 16
set_parameter_property DATA_WIDTH DISPLAY_NAME "Sample data width"
set_parameter_property DATA_WIDTH HDL_PARAMETER true

add_parameter FIFO_DEPTH INTEGER 1024
set_parameter_property FIFO_DEPTH DEFAULT_VALUE 1024
set_parameter_property FIFO_DEPTH DISPLAY_NAME "FIFO depth"
set_parameter_property FIFO_DEPTH HDL_PARAMETER true

add_parameter ALMOST_FULL_THRESHOLD INTEGER 768
set_parameter_property ALMOST_FULL_THRESHOLD DEFAULT_VALUE 768
set_parameter_property ALMOST_FULL_THRESHOLD DISPLAY_NAME "Almost-full threshold"
set_parameter_property ALMOST_FULL_THRESHOLD HDL_PARAMETER true

add_parameter ALMOST_EMPTY_THRESHOLD INTEGER 4
set_parameter_property ALMOST_EMPTY_THRESHOLD DEFAULT_VALUE 4
set_parameter_property ALMOST_EMPTY_THRESHOLD DISPLAY_NAME "Almost-empty threshold"
set_parameter_property ALMOST_EMPTY_THRESHOLD HDL_PARAMETER true

add_interface clock clock end
set_interface_property clock clockRate 0
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset_n reset_n Input 1

add_interface sample_sink avalon_streaming end
set_interface_property sample_sink associatedClock clock
set_interface_property sample_sink associatedReset reset
set_interface_property sample_sink dataBitsPerSymbol 16
set_interface_property sample_sink symbolsPerBeat 1
set_interface_property sample_sink readyLatency 0
add_interface_port sample_sink in_data data Input DATA_WIDTH
add_interface_port sample_sink in_valid valid Input 1
add_interface_port sample_sink in_ready ready Output 1

add_interface avs avalon end
set_interface_property avs addressUnits WORDS
set_interface_property avs associatedClock clock
set_interface_property avs associatedReset reset
set_interface_property avs readLatency 0
set_interface_property avs readWaitTime 1
set_interface_property avs writeWaitTime 0
set_interface_property avs timingUnits Cycles
add_interface_port avs avs_address address Input 3
add_interface_port avs avs_read read Input 1
add_interface_port avs avs_write write Input 1
add_interface_port avs avs_writedata writedata Input 32
add_interface_port avs avs_readdata readdata Output 32
add_interface_port avs avs_waitrequest waitrequest Output 1

add_interface status conduit end
set_interface_property status associatedClock clock
set_interface_property status associatedReset reset
add_interface_port status level level Output 32
add_interface_port status empty empty Output 1
add_interface_port status full full Output 1
add_interface_port status almost_full almost_full Output 1
add_interface_port status almost_empty almost_empty Output 1

add_interface irq interrupt end
set_interface_property irq associatedClock clock
set_interface_property irq associatedReset reset
add_interface_port irq irq irq Output 1
