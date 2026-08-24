# STP Tcl helper for live_stream OV7670 debug.
# Run from quartus_stp_tcl.exe with:
#   source camera_debug.tcl
# Then use:
#   connect_live_stream
#   sample_once
#   sample_loop 20 100

package require ::quartus::jtag
package require ::quartus::insystem_source_probe

array set probe_present {}

proc _close_probe_session {} {
    catch {end_insystem_source_probe}
}

proc _bit {value index} {
    expr {($value >> $index) & 1}
}

proc _bits {value msb lsb} {
    expr {($value >> $lsb) & ((1 << ($msb - $lsb + 1)) - 1)}
}

proc connect_live_stream {} {
    global hw dev probe_present

    _close_probe_session

    set hw [lindex [get_hardware_names] 0]
    if {$hw eq ""} {
        error "No JTAG hardware found."
    }

    set dev [lindex [get_device_names -hardware_name $hw] 0]
    if {$dev eq ""} {
        error "No JTAG device found on $hw."
    }

    set instances [get_insystem_source_probe_instance_info -hardware_name $hw -device_name $dev]
    array unset probe_present
    foreach inst $instances {
        set idx [lindex $inst 0]
        set name [lindex $inst 3]
        set probe_present($idx) 1
        set probe_present($name) $idx
    }
    puts "HW=$hw"
    puts "DEV=$dev"
    puts "INSTANCES=$instances"
}

proc _read_probe_if_present {index} {
    global probe_present

    if {[info exists probe_present($index)]} {
        return [read_probe_data -instance_index $index -value_in_hex]
    }
    return ""
}

proc _require_hex {hex_value label} {
    if {$hex_value eq ""} {
        error "Missing probe data for $label. Run connect_live_stream again after ending any active probe session."
    }
}

proc decode_stat {hex_value} {
    set v [expr 0x$hex_value]

    dict create \
        pll_locked      [_bit $v 0] \
        rst_n           [_bit $v 1] \
        i2c_done        [_bit $v 2] \
        cam_rd_recent   [_bit $v 3] \
        vga_wr_recent   [_bit $v 4] \
        vga_full_seen   [_bit $v 5] \
        cam_fifo_empty  [_bit $v 6] \
        cam_fifo_has    [_bit $v 7] \
        cam_rd_en       [_bit $v 8] \
        vga_fifo_full   [_bit $v 9] \
        vga_wr_en       [_bit $v 10] \
        frame_done      [_bit $v 11] \
        frame_stretch   [_bit $v 12] \
        pclk_heartbeat  [_bit $v 13] \
        vga_vs          [_bit $v 14] \
        pclk_present    [_bit $v 15] \
        vsync_present   [_bit $v 16] \
        href_present    [_bit $v 17] \
        cam_wr_recent   [_bit $v 18] \
        bypass          [_bit $v 19] \
        sw4             [_bit $v 20] \
        wr_rate         [_bits $v 22 21] \
        usedw           [_bits $v 31 23]
}

proc decode_geom {hex_value} {
    set v [expr 0x$hex_value]

    dict create \
        lines       [_bits $v 9 0] \
        pix_div256  [_bits $v 18 10] \
        frame_valid [_bit $v 19]
}

proc decode_pix {hex_value} {
    set v [expr 0x$hex_value]

    dict create \
        raw_first    [_bits $v 7 0] \
        raw_second   [_bits $v 15 8] \
        pixel_word   [_bits $v 31 16]
}

proc decode_vgst {hex_value} {
    set v [expr 0x$hex_value]

    dict create \
        h_count [_bits $v 9 0] \
        v_count [_bits $v 19 10] \
        usedw   [_bits $v 31 20]
}

proc decode_sch {hex_value} {
    set v [expr 0x$hex_value]

    dict create \
        new_frame_ready [_bit $v 31] \
        read_frame_valid [_bit $v 30] \
        vga_vsync_sync   [_bit $v 29] \
        vga_fifo_full    [_bit $v 28] \
        cam_fifo_empty   [_bit $v 27] \
        frame_done_sync  [_bit $v 26] \
        rd_req           [_bit $v 25] \
        vga_wr_pending   [_bit $v 24] \
        state            [_bits $v 23 20] \
        rd_ptr           [_bits $v 19 0]
}

proc decode_bar_pair {hex_value} {
    set v [expr 0x$hex_value]

    dict create \
        pixel_a [_bits $v 31 16] \
        pixel_b [_bits $v 15 0]
}

proc format_pair_series {hex_a hex_b hex_c hex_d} {
    set p0 [decode_bar_pair $hex_a]
    set p1 [decode_bar_pair $hex_b]
    set p2 [decode_bar_pair $hex_c]
    set p3 [decode_bar_pair $hex_d]

    format "%04X,%04X,%04X,%04X,%04X,%04X,%04X,%04X" \
        [dict get $p0 pixel_a] [dict get $p0 pixel_b] \
        [dict get $p1 pixel_a] [dict get $p1 pixel_b] \
        [dict get $p2 pixel_a] [dict get $p2 pixel_b] \
        [dict get $p3 pixel_a] [dict get $p3 pixel_b]
}

proc format_pair {hex_value} {
    set p [decode_bar_pair $hex_value]
    format "%04X,%04X" [dict get $p pixel_a] [dict get $p pixel_b]
}

proc decode_cfg0 {hex_value} {
    set v [expr 0x$hex_value]

    dict create \
        com7   [_bits $v 31 24] \
        com15  [_bits $v 23 16] \
        com17  [_bits $v 15 8] \
        rgb444 [_bits $v 7 0]
}

proc decode_cfg1 {hex_value} {
    set v [expr 0x$hex_value]

    dict create \
        tslb  [_bits $v 31 24] \
        com13 [_bits $v 23 16] \
        com3  [_bits $v 15 8] \
        com14 [_bits $v 7 0]
}

proc decode_cfg2 {hex_value} {
    set v [expr 0x$hex_value]

    dict create \
        xsc      [_bits $v 31 24] \
        ysc      [_bits $v 23 16] \
        dcwctr   [_bits $v 15 8] \
        pclk_div [_bits $v 7 0]
}

proc decode_cfg3 {hex_value} {
    set v [expr 0x$hex_value]

    dict create \
        pclk_delay [_bits $v 31 24] \
        clkrc      [_bits $v 23 16] \
        dblv       [_bits $v 15 8] \
        com10      [_bits $v 7 0]
}

proc _print_sample {index stat_hex geom_hex {pix_hex ""} {bar0_hex ""} {bar1_hex ""} {bar2_hex ""} {bar3_hex ""} {l0_hex ""} {l60_hex ""} {l120_hex ""} {l180_hex ""} {ol0_hex ""} {ol60_hex ""} {ol120_hex ""} {ol180_hex ""} {vgl0_hex ""} {vgl60_hex ""} {vgl120_hex ""} {vgl180_hex ""} {rl0_hex ""} {rl60_hex ""} {rl120_hex ""} {rl180_hex ""} {sch_hex ""} {cfg0_hex ""} {cfg1_hex ""} {cfg2_hex ""} {cfg3_hex ""} {cfr0_hex ""} {cfr1_hex ""} {cfr2_hex ""} {cfr3_hex ""} {vgr0_hex ""} {vgr1_hex ""} {vgr2_hex ""} {vgr3_hex ""} {ogr0_hex ""} {ogr1_hex ""} {ogr2_hex ""} {ogr3_hex ""} {vgst_hex ""} {rdr0_hex ""} {rdr1_hex ""} {rdr2_hex ""} {rdr3_hex ""} {uflo_hex ""} {camr0_hex ""} {camr1_hex ""} {camr2_hex ""} {camr3_hex ""}} {
    set stat [decode_stat $stat_hex]
    set geom [decode_geom $geom_hex]
    if {$pix_hex ne ""} {
        set pix [decode_pix $pix_hex]
        set pix_tail [format "  PIX=%s raw0=%02X raw1=%02X pixel=%04X" \
            $pix_hex \
            [dict get $pix raw_first] \
            [dict get $pix raw_second] \
            [dict get $pix pixel_word]]
    } else {
        set pix_tail ""
    }
    if {$bar0_hex ne ""} {
        set bar_tail [format "  BAR=%s" [format_pair_series $bar0_hex $bar1_hex $bar2_hex $bar3_hex]]
    } else {
        set bar_tail ""
    }
    if {$l0_hex ne ""} {
        set lines_tail [format "  L0=%s L60=%s L120=%s L180=%s" \
            [format_pair $l0_hex] \
            [format_pair $l60_hex] \
            [format_pair $l120_hex] \
            [format_pair $l180_hex]]
    } else {
        set lines_tail ""
    }
    if {$ol0_hex ne ""} {
        set olines_tail [format "  OL0=%s OL60=%s OL120=%s OL180=%s" \
            [format_pair $ol0_hex] \
            [format_pair $ol60_hex] \
            [format_pair $ol120_hex] \
            [format_pair $ol180_hex]]
    } else {
        set olines_tail ""
    }
    if {$vgl0_hex ne ""} {
        set vgl_tail [format "  VGL0=%s VGL60=%s VGL120=%s VGL180=%s" \
            [format_pair $vgl0_hex] \
            [format_pair $vgl60_hex] \
            [format_pair $vgl120_hex] \
            [format_pair $vgl180_hex]]
    } else {
        set vgl_tail ""
    }
    if {$rl0_hex ne ""} {
        set rlines_tail [format "  RL0=%s RL60=%s RL120=%s RL180=%s" \
            [format_pair $rl0_hex] \
            [format_pair $rl60_hex] \
            [format_pair $rl120_hex] \
            [format_pair $rl180_hex]]
    } else {
        set rlines_tail ""
    }
    if {$sch_hex ne ""} {
        set sch [decode_sch $sch_hex]
        set sch_tail [format "  SCH=%s nfr=%d rfv=%d vvs=%d vff=%d cfe=%d fds=%d rdrq=%d vwp=%d st=%d rdptr=%d" \
            $sch_hex \
            [dict get $sch new_frame_ready] \
            [dict get $sch read_frame_valid] \
            [dict get $sch vga_vsync_sync] \
            [dict get $sch vga_fifo_full] \
            [dict get $sch cam_fifo_empty] \
            [dict get $sch frame_done_sync] \
            [dict get $sch rd_req] \
            [dict get $sch vga_wr_pending] \
            [dict get $sch state] \
            [dict get $sch rd_ptr]]
    } else {
        set sch_tail ""
    }
    if {$cfg0_hex ne ""} {
        set cfg0 [decode_cfg0 $cfg0_hex]
        set cfg1 [decode_cfg1 $cfg1_hex]
        set cfg2 [decode_cfg2 $cfg2_hex]
        set cfg3 [decode_cfg3 $cfg3_hex]
        set cfg_tail [format "  CFG=com7=%02X com15=%02X com17=%02X rgb444=%02X tslb=%02X com13=%02X com3=%02X com14=%02X xsc=%02X ysc=%02X dcw=%02X pdiv=%02X pdly=%02X clkrc=%02X dblv=%02X com10=%02X" \
            [dict get $cfg0 com7] \
            [dict get $cfg0 com15] \
            [dict get $cfg0 com17] \
            [dict get $cfg0 rgb444] \
            [dict get $cfg1 tslb] \
            [dict get $cfg1 com13] \
            [dict get $cfg1 com3] \
            [dict get $cfg1 com14] \
            [dict get $cfg2 xsc] \
            [dict get $cfg2 ysc] \
            [dict get $cfg2 dcwctr] \
            [dict get $cfg2 pclk_div] \
            [dict get $cfg3 pclk_delay] \
            [dict get $cfg3 clkrc] \
            [dict get $cfg3 dblv] \
            [dict get $cfg3 com10]]
    } else {
        set cfg_tail ""
    }
    if {$cfr0_hex ne ""} {
        set cfr_tail [format "  CFR=%s" [format_pair_series $cfr0_hex $cfr1_hex $cfr2_hex $cfr3_hex]]
    } else {
        set cfr_tail ""
    }
    if {$vgr0_hex ne ""} {
        set vgr_tail [format "  VGR=%s" [format_pair_series $vgr0_hex $vgr1_hex $vgr2_hex $vgr3_hex]]
    } else {
        set vgr_tail ""
    }
    if {$ogr0_hex ne ""} {
        set ogr_tail [format "  OGR=%s" [format_pair_series $ogr0_hex $ogr1_hex $ogr2_hex $ogr3_hex]]
    } else {
        set ogr_tail ""
    }
    if {$vgst_hex ne ""} {
        set vgst [decode_vgst $vgst_hex]
        set vgst_tail [format "  VGST=%s h=%d v=%d vusedw=%d" \
            $vgst_hex \
            [dict get $vgst h_count] \
            [dict get $vgst v_count] \
            [dict get $vgst usedw]]
    } else {
        set vgst_tail ""
    }
    if {$rdr0_hex ne ""} {
        set rdr_tail [format "  RDR=%s" [format_pair_series $rdr0_hex $rdr1_hex $rdr2_hex $rdr3_hex]]
    } else {
        set rdr_tail ""
    }
    if {$camr0_hex ne ""} {
        set camr_tail [format "  CAMR=%s" [format_pair_series $camr0_hex $camr1_hex $camr2_hex $camr3_hex]]
    } else {
        set camr_tail ""
    }
    if {$uflo_hex ne ""} {
        set uflo_tail [format "  UFLO=%u" [expr 0x$uflo_hex]]
    } else {
        set uflo_tail ""
    }

    puts [format "#%02d STAT=%s bypass=%d pclk=%d vs=%d href=%d wr_rate=%d wr_recent=%d empty=%d has=%d usedw=%d  GEOM=%s lines=%d pix_div256=%d frame_valid=%d%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s" \
        $index \
        $stat_hex \
        [dict get $stat bypass] \
        [dict get $stat pclk_present] \
        [dict get $stat vsync_present] \
        [dict get $stat href_present] \
        [dict get $stat wr_rate] \
        [dict get $stat cam_wr_recent] \
        [dict get $stat cam_fifo_empty] \
        [dict get $stat cam_fifo_has] \
        [dict get $stat usedw] \
        $geom_hex \
        [dict get $geom lines] \
        [dict get $geom pix_div256] \
        [dict get $geom frame_valid] \
        $pix_tail \
        $bar_tail \
        $lines_tail \
        $olines_tail \
        $vgl_tail \
        $rlines_tail \
        $sch_tail \
        $cfg_tail \
        $cfr_tail \
        $vgr_tail \
        $ogr_tail \
        $vgst_tail \
        $rdr_tail \
        $camr_tail \
        $uflo_tail]
}

proc sample_once {} {
    global hw dev

    _close_probe_session
    start_insystem_source_probe -hardware_name $hw -device_name $dev
    set stat_hex [_read_probe_if_present 0]
    set geom_hex [_read_probe_if_present 1]
    set pix_hex  [_read_probe_if_present 2]
    set bar0_hex [_read_probe_if_present 3]
    set bar1_hex [_read_probe_if_present 4]
    set bar2_hex [_read_probe_if_present 5]
    set bar3_hex [_read_probe_if_present 6]
    set l0_hex   [_read_probe_if_present 33]
    set l60_hex  [_read_probe_if_present 34]
    set l120_hex [_read_probe_if_present 35]
    set l180_hex [_read_probe_if_present 36]
    set ol0_hex   [_read_probe_if_present 37]
    set ol60_hex  [_read_probe_if_present 38]
    set ol120_hex [_read_probe_if_present 39]
    set ol180_hex [_read_probe_if_present 40]
    set vgl0_hex   [_read_probe_if_present 41]
    set vgl60_hex  [_read_probe_if_present 42]
    set vgl120_hex [_read_probe_if_present 43]
    set vgl180_hex [_read_probe_if_present 44]
    set rl0_hex    [_read_probe_if_present 45]
    set rl60_hex   [_read_probe_if_present 46]
    set rl120_hex  [_read_probe_if_present 47]
    set rl180_hex  [_read_probe_if_present 48]
    set sch_hex    [_read_probe_if_present 49]
    set cfg0_hex [_read_probe_if_present 7]
    set cfg1_hex [_read_probe_if_present 8]
    set cfg2_hex [_read_probe_if_present 9]
    set cfg3_hex [_read_probe_if_present 10]
    set cfr0_hex [_read_probe_if_present 11]
    set cfr1_hex [_read_probe_if_present 12]
    set cfr2_hex [_read_probe_if_present 13]
    set cfr3_hex [_read_probe_if_present 14]
    set vgr0_hex [_read_probe_if_present 15]
    set vgr1_hex [_read_probe_if_present 16]
    set vgr2_hex [_read_probe_if_present 17]
    set vgr3_hex [_read_probe_if_present 18]
    set ogr0_hex [_read_probe_if_present 19]
    set ogr1_hex [_read_probe_if_present 20]
    set ogr2_hex [_read_probe_if_present 21]
    set ogr3_hex [_read_probe_if_present 22]
    set vgst_hex [_read_probe_if_present 23]
    set rdr0_hex [_read_probe_if_present 24]
    set rdr1_hex [_read_probe_if_present 25]
    set rdr2_hex [_read_probe_if_present 26]
    set rdr3_hex [_read_probe_if_present 27]
    set uflo_hex [_read_probe_if_present 28]
    set camr0_hex [_read_probe_if_present 29]
    set camr1_hex [_read_probe_if_present 30]
    set camr2_hex [_read_probe_if_present 31]
    set camr3_hex [_read_probe_if_present 32]
    _require_hex $stat_hex "STAT"
    _require_hex $geom_hex "GEOM"
    _print_sample 0 $stat_hex $geom_hex $pix_hex $bar0_hex $bar1_hex $bar2_hex $bar3_hex $l0_hex $l60_hex $l120_hex $l180_hex $ol0_hex $ol60_hex $ol120_hex $ol180_hex $vgl0_hex $vgl60_hex $vgl120_hex $vgl180_hex $rl0_hex $rl60_hex $rl120_hex $rl180_hex $sch_hex $cfg0_hex $cfg1_hex $cfg2_hex $cfg3_hex $cfr0_hex $cfr1_hex $cfr2_hex $cfr3_hex $vgr0_hex $vgr1_hex $vgr2_hex $vgr3_hex $ogr0_hex $ogr1_hex $ogr2_hex $ogr3_hex $vgst_hex $rdr0_hex $rdr1_hex $rdr2_hex $rdr3_hex $uflo_hex $camr0_hex $camr1_hex $camr2_hex $camr3_hex
    _close_probe_session
}

proc sample_loop {{count 20} {delay_ms 100}} {
    global hw dev

    _close_probe_session
    start_insystem_source_probe -hardware_name $hw -device_name $dev
    for {set i 0} {$i < $count} {incr i} {
        set stat_hex [_read_probe_if_present 0]
        set geom_hex [_read_probe_if_present 1]
        set pix_hex  [_read_probe_if_present 2]
        set bar0_hex [_read_probe_if_present 3]
        set bar1_hex [_read_probe_if_present 4]
        set bar2_hex [_read_probe_if_present 5]
        set bar3_hex [_read_probe_if_present 6]
        set l0_hex   [_read_probe_if_present 33]
        set l60_hex  [_read_probe_if_present 34]
        set l120_hex [_read_probe_if_present 35]
        set l180_hex [_read_probe_if_present 36]
        set ol0_hex   [_read_probe_if_present 37]
        set ol60_hex  [_read_probe_if_present 38]
        set ol120_hex [_read_probe_if_present 39]
        set ol180_hex [_read_probe_if_present 40]
        set vgl0_hex   [_read_probe_if_present 41]
        set vgl60_hex  [_read_probe_if_present 42]
        set vgl120_hex [_read_probe_if_present 43]
        set vgl180_hex [_read_probe_if_present 44]
        set rl0_hex    [_read_probe_if_present 45]
        set rl60_hex   [_read_probe_if_present 46]
        set rl120_hex  [_read_probe_if_present 47]
        set rl180_hex  [_read_probe_if_present 48]
        set sch_hex    [_read_probe_if_present 49]
        set cfg0_hex [_read_probe_if_present 7]
        set cfg1_hex [_read_probe_if_present 8]
        set cfg2_hex [_read_probe_if_present 9]
        set cfg3_hex [_read_probe_if_present 10]
        set cfr0_hex [_read_probe_if_present 11]
        set cfr1_hex [_read_probe_if_present 12]
        set cfr2_hex [_read_probe_if_present 13]
        set cfr3_hex [_read_probe_if_present 14]
        set vgr0_hex [_read_probe_if_present 15]
        set vgr1_hex [_read_probe_if_present 16]
        set vgr2_hex [_read_probe_if_present 17]
        set vgr3_hex [_read_probe_if_present 18]
        set ogr0_hex [_read_probe_if_present 19]
        set ogr1_hex [_read_probe_if_present 20]
        set ogr2_hex [_read_probe_if_present 21]
        set ogr3_hex [_read_probe_if_present 22]
        set vgst_hex [_read_probe_if_present 23]
        set rdr0_hex [_read_probe_if_present 24]
        set rdr1_hex [_read_probe_if_present 25]
        set rdr2_hex [_read_probe_if_present 26]
        set rdr3_hex [_read_probe_if_present 27]
        set uflo_hex [_read_probe_if_present 28]
        set camr0_hex [_read_probe_if_present 29]
        set camr1_hex [_read_probe_if_present 30]
        set camr2_hex [_read_probe_if_present 31]
        set camr3_hex [_read_probe_if_present 32]
        _require_hex $stat_hex "STAT"
        _require_hex $geom_hex "GEOM"
        _print_sample $i $stat_hex $geom_hex $pix_hex $bar0_hex $bar1_hex $bar2_hex $bar3_hex $l0_hex $l60_hex $l120_hex $l180_hex $ol0_hex $ol60_hex $ol120_hex $ol180_hex $vgl0_hex $vgl60_hex $vgl120_hex $vgl180_hex $rl0_hex $rl60_hex $rl120_hex $rl180_hex $sch_hex $cfg0_hex $cfg1_hex $cfg2_hex $cfg3_hex $cfr0_hex $cfr1_hex $cfr2_hex $cfr3_hex $vgr0_hex $vgr1_hex $vgr2_hex $vgr3_hex $ogr0_hex $ogr1_hex $ogr2_hex $ogr3_hex $vgst_hex $rdr0_hex $rdr1_hex $rdr2_hex $rdr3_hex $uflo_hex $camr0_hex $camr1_hex $camr2_hex $camr3_hex
        after $delay_ms
    }
    _close_probe_session
}

proc quick_summary {} {
    puts "Expected healthy frame: lines=240 pix_div256=300 frame_valid=1"
    puts "Useful commands:"
    puts "  connect_live_stream"
    puts "  sample_once"
    puts "  sample_loop 20 100"
    puts "Sample output now includes PIX, camera BAR, SCCB CFG, camera-FIFO read CFR, VGA-write VGR, VGA output OGR, VGST status, and VGA read-stream RDR."
}
