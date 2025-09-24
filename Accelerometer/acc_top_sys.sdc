#SDC file: acc_top_sys.sdc


# clock uncertainty:
derive_clock_uncertainty

# system clock 50 MHz:
create_clock -name internal_system_clock_50MHz -period 20.000 [get_ports {clock_50}]


# make use of the internal pll
derive_pll_clocks -create_base_clocks


# signals out to analyze (timming):
set_output_delay -clock { internal_system_clock_50MHz } -min 1 [get_ports {vga_* hex* ss_n o_mosi, sclk }]
set_output_delay -clock { internal_system_clock_50MHz } -max 2.05 [get_ports {vga_* hex* ss_n mosi, sclk}]

# False paths signals not to be analyze:
set_false_path -from [get_ports {miso reset_n}]

# False paths output not to be analyze:

# Disable non used pins
set_false_path -from [get_ports {altera_reserved_tck altera_reserved_tdi altera_reserved_tms}]
set_false_path -to [get_ports {altera_reserved_tdo}]