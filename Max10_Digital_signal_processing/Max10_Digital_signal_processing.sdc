# Timing constraints for Max10_Digital_signal_processing
# Board oscillator: 50 MHz on MAX10_CLK1_50

set_time_format -unit ns -decimal_places 3

# Main board clock
create_clock -name clk_50 -period 20.000 [get_ports {MAX10_CLK1_50}]

# Let Quartus derive any PLL-generated clocks inside the Qsys system.
derive_pll_clocks -create_base_clocks
derive_clock_uncertainty

# Treat button and switch paths as asynchronous control signals.
set_false_path -from [get_ports {KEY[*]}] -to [all_registers]
set_false_path -from [get_ports {SW[*]}] -to [all_registers]

# LED outputs are not timing-critical data paths.
set_false_path -from [all_registers] -to [get_ports {LEDR[*]}]

# Keep JTAG clock separate from the board clock.
set_clock_groups -asynchronous -group {altera_reserved_tck}

# SDRAM external timing from IS42S16320D datasheet (100 MHz, CAS latency 3):
# address/command/CKE/DQM setup = 1.5 ns; hold = 0.8 ns.
# The -max/-min output-delay signs express setup and hold relative to the
# phase-shifted DRAM clock at the SDRAM device.
set dram_clk [get_clocks {u0|altpll_0|sd1|pll7|clk[2]}]
set_false_path \
    -from [get_clocks {u0|altpll_0|sd1|pll7|clk[2]}] \
    -to [get_ports {DRAM_CLK}]
set_output_delay -clock $dram_clk -max 1.5 \
	[get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_CAS_N DRAM_CKE DRAM_CS_N DRAM_LDQM DRAM_UDQM DRAM_RAS_N DRAM_WE_N}]
set_output_delay -clock $dram_clk -min -0.8 \
	[get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_CAS_N DRAM_CKE DRAM_CS_N DRAM_LDQM DRAM_UDQM DRAM_RAS_N DRAM_WE_N}]

# DRAM_DQ is bidirectional. Its read-data input timing requires a separate
# SDRAM model/input-delay constraint and is not covered by output delays.
set_false_path -from [all_registers] -to [get_ports {DRAM_DQ[*]}]
set_false_path -from [get_ports {DRAM_DQ[*]}] -to [all_registers]



set_false_path -from [get_ports {altera_reserved_tdi}] -to [all_registers]
set_false_path -from [get_ports {altera_reserved_tms}] -to [all_registers]
set_false_path -from [all_registers] -to [get_ports {altera_reserved_tdo}]

set_clock_groups -asynchronous -group {altera_reserved_tck}
