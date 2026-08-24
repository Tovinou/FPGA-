package require -exact qsys 25.1

load_system adc_c.qsys

proc ensure_pio {inst_name} {
    if { [lsearch -exact [get_instances] $inst_name] < 0 } {
        add_instance $inst_name altera_avalon_pio 25.1
        set_instance_parameter_value $inst_name width 8
        set_instance_parameter_value $inst_name direction Output
    }
}

ensure_pio hex0_pio
ensure_pio hex1_pio
ensure_pio hex2_pio
ensure_pio hex3_pio
ensure_pio hex4_pio
ensure_pio hex5_pio

proc ensure_conn {start end base} {
    if { [lsearch -exact [get_connections] "$start/$end"] < 0 } {
        add_connection $start $end
    }
    set_connection_parameter_value "$start/$end" baseAddress $base
}

ensure_conn intel_niosv_m_0.data_manager hex0_pio.s1 0x000300A0
ensure_conn intel_niosv_m_0.data_manager hex1_pio.s1 0x000300B0
ensure_conn intel_niosv_m_0.data_manager hex2_pio.s1 0x000300C0
ensure_conn intel_niosv_m_0.data_manager hex3_pio.s1 0x000300D0
ensure_conn intel_niosv_m_0.data_manager hex4_pio.s1 0x000300E0
ensure_conn intel_niosv_m_0.data_manager hex5_pio.s1 0x000300F0

foreach inst {hex0_pio hex1_pio hex2_pio hex3_pio hex4_pio hex5_pio} {
    if { [lsearch -exact [get_connections] "altpll_0.c0/$inst.clk"] < 0 } {
        add_connection altpll_0.c0 $inst.clk
    }
    if { [lsearch -exact [get_connections] "clk_0.clk_reset/$inst.reset"] < 0 } {
        add_connection clk_0.clk_reset $inst.reset
    }
    if { [lsearch -exact [get_connections] "intel_niosv_m_0.dbg_reset_out/$inst.reset"] < 0 } {
        add_connection intel_niosv_m_0.dbg_reset_out $inst.reset
    }
}

proc ensure_export {if_name internal} {
    if { [lsearch -exact [get_interfaces] $if_name] < 0 } {
        add_interface $if_name conduit end
    }
    set_interface_property $if_name EXPORT_OF $internal
}

ensure_export hex0 hex0_pio.external_connection
ensure_export hex1 hex1_pio.external_connection
ensure_export hex2 hex2_pio.external_connection
ensure_export hex3 hex3_pio.external_connection
ensure_export hex4 hex4_pio.external_connection
ensure_export hex5 hex5_pio.external_connection

save_system adc_c.qsys

