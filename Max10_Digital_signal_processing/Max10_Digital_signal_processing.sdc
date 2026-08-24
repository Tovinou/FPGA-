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

set_false_path -from [get_ports {altera_reserved_tdi}] -to [all_registers]
set_false_path -from [get_ports {altera_reserved_tms}] -to [all_registers]
set_false_path -from [all_registers] -to [get_ports {altera_reserved_tdo}]

set_clock_groups -asynchronous -group {altera_reserved_tck}
