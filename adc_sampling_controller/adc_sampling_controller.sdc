create_clock -name MAX10_CLK1_50 -period 20.000 [get_ports {MAX10_CLK1_50}]
derive_pll_clocks
derive_clock_uncertainty

set_input_delay -clock MAX10_CLK1_50 0.000 [get_ports {KEY[*] SW[*]}]
set_output_delay -clock MAX10_CLK1_50 0.000 [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*] ARDUINO_IO[*]}]

set_false_path -from [get_ports {altera_reserved_tdi altera_reserved_tms}]
set_false_path -to [get_ports {altera_reserved_tdo}]

set_input_delay -clock altera_reserved_tck 0.000 [get_ports {altera_reserved_tdi altera_reserved_tms}]
set_output_delay -clock altera_reserved_tck 0.000 [get_ports {altera_reserved_tdo}]
