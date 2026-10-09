# TCL File Generated for Platform Designer
# Custom SDRAM controller packaged from the Terasic DE10-Lite
# SDRAM_Nios_Test generated Avalon SDRAM HDL (replacement for
# altera_avalon_new_sdram_controller, which is not in Quartus 25.1).
#
# Clock this component from the system PLL c0 (100 MHz). Export PLL c1
# as DRAM_CLK (phase-shifted) at the top level.

# Compatible with Platform Designer in Quartus 16.x through 25.1
if {[catch {package require qsys}]} {
    catch {package require -exact qsys 16.0}
}

set_module_property NAME mycustom_sdram
set_module_property VERSION 1.0
set_module_property DISPLAY_NAME "Custom SDRAM Controller (DE10-Lite)"
set_module_property DESCRIPTION "Avalon-MM SDRAM controller for the DE10-Lite 64 MByte 16-bit SDRAM. HDL is the Terasic SDRAM_Nios_Test controller (IS42S16320 / MT48LC-compatible timings, CAS latency 3, 100 MHz)."
set_module_property GROUP "Memory Interfaces and Controllers"
set_module_property AUTHOR Terasic/Custom
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE false
set_module_property REPORT_TO_TALKBACK false
set_module_property ALLOW_GREYBOX_GENERATION false
set_module_property REPORT_HIERARCHY false

add_documentation_link "DE10-Lite SDRAM constraints" "../../Max10_Digital_signal_processing.sdc"

# -----------------------------------------------------------------------------
# Files
# -----------------------------------------------------------------------------
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL mycustom_sdram
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
add_fileset_file mycustom_sdram.v VERILOG PATH HDL/mycustom_sdram.v TOP_LEVEL_FILE

add_fileset SIM_VERILOG SIM_VERILOG "" ""
set_fileset_property SIM_VERILOG TOP_LEVEL mycustom_sdram
add_fileset_file mycustom_sdram.v VERILOG PATH HDL/mycustom_sdram.v

# -----------------------------------------------------------------------------
# Clock / reset  (connect clock to PLL c0 = 100 MHz system clock)
# -----------------------------------------------------------------------------
add_interface clk clock end
set_interface_property clk clockRate 100000000
set_interface_property clk ENABLED true
set_interface_property clk EXPORT_OF ""
set_interface_property clk PORT_NAME_MAP ""
set_interface_property clk CMSIS_SVD_VARIABLES ""
set_interface_property clk SVD_ADDRESS_GROUP ""
add_interface_port clk clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clk
set_interface_property reset synchronousEdges DEASSERT
set_interface_property reset ENABLED true
add_interface_port reset reset_n reset_n Input 1

# -----------------------------------------------------------------------------
# Avalon-MM slave
# 25-bit word address * 16-bit data = 64 MByte
# -----------------------------------------------------------------------------
add_interface s1 avalon end
set_interface_property s1 addressUnits WORDS
set_interface_property s1 associatedClock clk
set_interface_property s1 associatedReset reset
set_interface_property s1 bitsPerSymbol 8
set_interface_property s1 burstOnBurstBoundariesOnly false
set_interface_property s1 burstcountUnits WORDS
set_interface_property s1 explicitAddressSpan 67108864
set_interface_property s1 holdTime 0
set_interface_property s1 linewrapBursts false
set_interface_property s1 maximumPendingReadTransactions 1
set_interface_property s1 maximumPendingWriteTransactions 0
set_interface_property s1 readLatency 0
set_interface_property s1 readWaitTime 1
set_interface_property s1 setupTime 0
set_interface_property s1 timingUnits Cycles
set_interface_property s1 writeWaitTime 0
set_interface_property s1 ENABLED true

add_interface_port s1 az_addr address Input 25
add_interface_port s1 az_be_n byteenable_n Input 2
add_interface_port s1 az_cs chipselect Input 1
add_interface_port s1 az_data writedata Input 16
add_interface_port s1 az_rd_n read_n Input 1
add_interface_port s1 az_wr_n write_n Input 1
add_interface_port s1 za_data readdata Output 16
add_interface_port s1 za_valid readdatavalid Output 1
add_interface_port s1 za_waitrequest waitrequest Output 1

set_interface_assignment s1 embeddedsw.configuration.isFlash 0
set_interface_assignment s1 embeddedsw.configuration.isMemoryDevice 1
set_interface_assignment s1 embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment s1 embeddedsw.configuration.isPrintableDevice 0
set_interface_assignment s1 embeddedsw.memoryInfo.IS_MEMORY_DEVICE 1
set_interface_assignment s1 embeddedsw.memoryInfo.memType SDRAM

# -----------------------------------------------------------------------------
# External SDRAM pins (export as conduit to DRAM_* at the board top)
# -----------------------------------------------------------------------------
add_interface wire conduit end
set_interface_property wire associatedClock clk
set_interface_property wire associatedReset none
set_interface_property wire ENABLED true

add_interface_port wire zs_addr addr Output 13
add_interface_port wire zs_ba ba Output 2
add_interface_port wire zs_cas_n cas_n Output 1
add_interface_port wire zs_cke cke Output 1
add_interface_port wire zs_cs_n cs_n Output 1
add_interface_port wire zs_dq dq Bidir 16
add_interface_port wire zs_dqm dqm Output 2
add_interface_port wire zs_ras_n ras_n Output 1
add_interface_port wire zs_we_n we_n Output 1
