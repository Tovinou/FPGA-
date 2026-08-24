
project_open live_stream
create_timing_netlist -model slow
read_sdc
update_timing_netlist
report_timing -setup -npaths 3 -to [get_ports {DRAM_DQ[*]}] -file output_files/timing_out.txt

