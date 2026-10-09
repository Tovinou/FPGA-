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

proc _require_live_stream_connection {} {
    global hw dev

    if {![info exists hw] || ![info exists dev] || $hw eq "" || $dev eq ""} {
        error "No connected JTAG device. Run connect_live_stream successfully first."
    }
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

    unset -nocomplain hw dev
    array unset probe_present

    if {[catch {set hardware_names [get_hardware_names]} message]} {
        error "Could not enumerate JTAG hardware: $message"
    }
    if {[llength $hardware_names] == 0} {
        error "No JTAG hardware found. Check the USB-Blaster connection and driver."
    }

    set connection_found 0
    foreach candidate $hardware_names {
        if {[catch {set devices [get_device_names -hardware_name $candidate]}]} {
            continue
        }
        if {[llength $devices] == 0} {
            continue
        }

        set hw $candidate
        set dev [lindex $devices 0]
        if {[catch {set instances [get_insystem_source_probe_instance_info -hardware_name $hw -device_name $dev]} message]} {
            set failed_hw $hw
            unset -nocomplain hw dev
            error "Found $failed_hw but could not query its SignalTap probes: $message"
        }
        set connection_found 1
        break
    }
    if {!$connection_found} {
        error "No accessible JTAG device found. Check the cable, power, and whether another Quartus process is using it."
    }

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

    _require_live_stream_connection
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

    _require_live_stream_connection
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

proc check_switches_ok {} {
    puts "=== Required switch positions for 'all SW down = correct live camera view'"
    puts ""
    puts "  SW#  POS   Meaning (this build)"
    puts "  ---  ----  ----------------------------------------------------------"
    puts "   0   DOWN  VGA test bars OFF; live camera stream ON"
    puts "        UP   8 pure-color vertical bars (vga_interface self-test)"
    puts "   1   DOWN  VSYNC/HREF polarity: non-invert (correct for most OV7670)"
    puts "        UP   Invert both VSYNC+HREF (use only if frame always blank)"
    puts "   2   DOWN  Unused (free for user debug)"
    puts "   3   DOWN  SDRAM framebuffer path USED (correct for stable frame)"
    puts "   !!!! UP   BYPASS SDRAM (camera->VGA direct) -- causes TEARING/STREAK"
    puts "   4   DOWN  Unused (free for user debug)"
    puts "   5   DOWN  Unused (free for user debug)"
    puts "   6   DOWN  D[7:0] bit order: normal (no reverse)"
    puts "        UP   Reverse D[7:0] bit order (debug only, WRONG for capture)"
    puts "   7   DOWN  Byte-swap ON (correct for OV7670 TSLB=0x0C default)"
    puts "        UP   Byte-swap OFF (override; reproduce the magenta/yellow pic)"
    puts "   8   DOWN  }"
    puts "   9   DOWN  } data_map_sel=00: D[7:0] straight passthrough (RIGHT)"
    puts "       UP-DN } sel=01: nibble-swap  -> colours WRONG"
    puts "       DN-UP } sel=10: 2-bit-rotate -> colours WRONG"
    puts "       UP-UP } sel=11: nibble-swap  -> colours WRONG"
    puts ""
    puts "If ANY of SW(9), SW(8), SW(7), SW(6), SW(3), SW(1), SW(0) are wrong,"
    puts "the output CANNOT look correct even if all RTL is fixed."
    puts ""
    puts "Recommended BEFORE running any other TCL command:"
    puts "  (a) Physically verify all 10 toggles point AWAY from the DE10-Lite"
    puts "      board label text (that is the '0' / DOWN position)."
    puts "  (b) Then, and only then, run: sample_once"
}

proc quick_summary {} {
    puts "Expected healthy frame: lines=240 pix_div256=300 frame_valid=1"
    puts "Useful commands (in order):"
    puts "  check_switches_ok          -- first: correct physical SW positions"
    puts "  connect_live_stream        -- then: open JTAG probe session"
    puts "  sample_once                -- capture geometry summary (lines/pixels)"
    puts "  check_camera_inputs 200 25 -- confirm PCLK/HREF/VSYNC + all D toggle"
    puts "  check_camera_sccb          -- prove I2C writes (i2c_done + 16/16 regs)"
    puts "  print_ref_pixels           -- 8 ref-pixels both byte orders + Y"
    puts "  sample_loop 20 100         -- monitor frame geometry 20 times"
    puts ""
    puts "Sample output now includes PIX, camera BAR, SCCB CFG, camera-FIFO read"
    puts "  CFR, VGA-write VGR, VGA output OGR, VGST status, and VGA RDR stream."
    puts "check_camera_sccb : fresh JTAG session; i2c_done + 16 OV reg exact matches"
    puts "print_ref_pixels  : 8 line-1 pixels, both RGB565 byte orders, plus Y luminance"
    puts "check_switches_ok : prints correct switch matrix for default live camera"
    puts ""
    puts "NOTE: if commands added after 'check_camera_sccb' report invalid name,"
    puts "      type:  source camera_debug.tcl    to reload the script in this session."
}

proc check_camera_inputs {{samples 200} {delay_ms 25}} {
    global hw dev

    _require_live_stream_connection
    if {$samples < 2} {
        error "Use at least 2 samples."
    }

    puts "Checking camera activity over $samples samples (${delay_ms}ms interval)."
    puts "For direct D\[7:0\] checks, set SW(6)=0 and SW(9:8)=00."

    _close_probe_session
    start_insystem_source_probe -hardware_name $hw -device_name $dev

    set pclk_seen 0
    set href_seen 0
    set vsync_seen 0
    set zero_seen 0
    set one_seen 0
    set toggle_seen 0
    set previous_bytes ""

    for {set sample 0} {$sample < $samples} {incr sample} {
        set stat_hex [_read_probe_if_present 0]
        set pix_hex [_read_probe_if_present 2]
        _require_hex $stat_hex "STAT"
        _require_hex $pix_hex "PIX"

        set stat [decode_stat $stat_hex]
        set pix [decode_pix $pix_hex]
        if {[dict get $stat pclk_present]} {set pclk_seen 1}
        if {[dict get $stat href_present]} {set href_seen 1}
        if {[dict get $stat vsync_present]} {set vsync_seen 1}

        set current_bytes [list [dict get $pix raw_first] [dict get $pix raw_second]]
        foreach byte $current_bytes {
            set zero_seen [expr {$zero_seen | ((~$byte) & 255)}]
            set one_seen [expr {$one_seen | $byte}]
        }
        if {$previous_bytes ne ""} {
            foreach previous $previous_bytes current $current_bytes {
                set toggle_seen [expr {$toggle_seen | ($previous ^ $current)}]
            }
        }
        set previous_bytes $current_bytes
        after $delay_ms
    }

    _close_probe_session

    set failed 0
    foreach {name observed} [list PCLK $pclk_seen HREF $href_seen VSYNC $vsync_seen] {
        set result [expr {$observed ? "ACTIVE" : "NO ACTIVITY"}]
        puts [format "%s: %s" $name $result]
        if {!$observed} {set failed 1}
    }

    set unverified_bits {}
    for {set bit 7} {$bit >= 0} {incr bit -1} {
        set mask [expr {1 << $bit}]
        set saw_zero [expr {($zero_seen & $mask) != 0}]
        set saw_one [expr {($one_seen & $mask) != 0}]
        set toggled [expr {($toggle_seen & $mask) != 0}]
        set result [expr {$saw_zero && $saw_one && $toggled ? "TOGGLING" : "NO TOGGLE"}]
        puts [format "D%d: %s (saw 0=%d, 1=%d)" $bit $result $saw_zero $saw_one]
        if {!($saw_zero && $saw_one && $toggled)} {
            lappend unverified_bits $bit
        }
    }

    if {[llength $unverified_bits] == 0 && !$failed} {
        puts "RESULT: all monitored camera signals are active; all D bits toggled."
    } elseif {[llength $unverified_bits] > 0} {
        puts "RESULT: inconclusive for D bits $unverified_bits. Aim at a detailed, moving scene and repeat."
    } else {
        puts "RESULT: one or more clock/sync signals showed no activity."
    }
}

proc check_camera_sccb {} {
    global hw dev probe_present

    puts "=== check_camera_sccb ==="
    puts "Requires a fresh JTAG connection. Dropping any existing session..."

    _close_probe_session
    unset -nocomplain hw dev
    array unset probe_present

    puts "Re-enumerating JTAG chain..."
    if {[catch {set hardware_names [get_hardware_names]} message]} {
        error "Could not enumerate JTAG hardware: $message"
    }
    if {[llength $hardware_names] == 0} {
        error "No JTAG hardware found. Check the USB-Blaster connection and driver."
    }

    set connection_found 0
    foreach candidate $hardware_names {
        if {[catch {set devices [get_device_names -hardware_name $candidate]}]} {
            continue
        }
        if {[llength $devices] == 0} {
            continue
        }
        set hw $candidate
        set dev [lindex $devices 0]
        if {[catch {set instances [get_insystem_source_probe_instance_info -hardware_name $hw -device_name $dev]} message]} {
            set failed_hw $hw
            unset -nocomplain hw dev
            error "Found $failed_hw but could not query its SignalTap probes: $message"
        }
        set connection_found 1
        break
    }
    if {!$connection_found} {
        error "No accessible JTAG device found. Check the cable, power, and whether another Quartus process is using it."
    }

    foreach inst $instances {
        set idx [lindex $inst 0]
        set name [lindex $inst 3]
        set probe_present($idx) 1
        set probe_present($name) $idx
    }
    puts "HW=$hw"
    puts "DEV=$dev"

    set expected [dict create \
        COM7         0x14 \
        COM15        0xD0 \
        COM17        0x00 \
        RGB444       0x00 \
        TSLB         0x0C \
        COM13        0x83 \
        COM3         0x04 \
        COM14        0x19 \
        XSC          0x3A \
        YSC          0x35 \
        DCWCTR       0x11 \
        PCLK_DIV     0xF1 \
        PCLK_DELAY   0x02 \
        CLKRC        0x01 \
        DBLV         0x0A \
        COM10        0x02 \
    ]

    set reg_names [list COM7 COM15 COM17 RGB444 TSLB COM13 COM3 COM14 XSC YSC DCWCTR PCLK_DIV PCLK_DELAY CLKRC DBLV COM10]
    set reg_addrs [list 0x12 0x40 0x42 0x8C 0x3A 0x3D 0x0C 0x3E 0x70 0x71 0x72 0x73 0xA2 0x11 0x6B 0x15]

    puts ""
    puts "Opening ISSP probe session..."
    start_insystem_source_probe -hardware_name $hw -device_name $dev

    set stat_hex [_read_probe_if_present 0]
    set cfg0_hex [_read_probe_if_present 7]
    set cfg1_hex [_read_probe_if_present 8]
    set cfg2_hex [_read_probe_if_present 9]
    set cfg3_hex [_read_probe_if_present 10]

    _close_probe_session

    _require_hex $stat_hex "STAT"
    _require_hex $cfg0_hex "CFG0"
    _require_hex $cfg1_hex "CFG1"
    _require_hex $cfg2_hex "CFG2"
    _require_hex $cfg3_hex "CFG3"

    set stat [decode_stat $stat_hex]
    set i2c_done_val [dict get $stat i2c_done]

    puts ""
    puts "--- i2c_done status ---"
    puts [format "i2c_done = %d  %s" $i2c_done_val [expr {$i2c_done_val ? "(configuration complete)" : "(STILL RUNNING / FAILED)"}]]

    set cfg0 [decode_cfg0 $cfg0_hex]
    set cfg1 [decode_cfg1 $cfg1_hex]
    set cfg2 [decode_cfg2 $cfg2_hex]
    set cfg3 [decode_cfg3 $cfg3_hex]

    set actual_values [list \
        [dict get $cfg0 com7]   [dict get $cfg0 com15]  [dict get $cfg0 com17]  [dict get $cfg0 rgb444] \
        [dict get $cfg1 tslb]   [dict get $cfg1 com13]  [dict get $cfg1 com3]   [dict get $cfg1 com14] \
        [dict get $cfg2 xsc]    [dict get $cfg2 ysc]    [dict get $cfg2 dcwctr]  [dict get $cfg2 pclk_div] \
        [dict get $cfg3 pclk_delay] [dict get $cfg3 clkrc] [dict get $cfg3 dblv]  [dict get $cfg3 com10] \
    ]

    puts ""
    puts "--- Register readback verification (16 registers via SCCB read) ---"
    puts [format "%-12s  %-6s  %-8s  %-8s  %s" "Register" "Addr" "Expected" "Actual" "Status"]
    puts "------------  ------  --------  --------  ----------"

    set mismatches {}
    for {set i 0} {$i < 16} {incr i} {
        set name [lindex $reg_names $i]
        set addr [lindex $reg_addrs $i]
        set exp  [dict get $expected $name]
        set act  [lindex $actual_values $i]
        if {$exp == $act} {
            set status "PASS"
        } else {
            set status "MISMATCH"
            lappend mismatches [list $name $addr $exp $act]
        }
        puts [format "%-12s  0x%02X    0x%02X      0x%02X      %s" $name $addr $exp $act $status]
    }

    puts ""
    puts "--- Result summary ---"
    set pass_count [expr {16 - [llength $mismatches]}]
    puts [format "i2c_done : %s" [expr {$i2c_done_val ? "ASSERTED (ok)" : "NOT ASSERTED (FAIL)"}]]
    puts [format "Registers: %d/16 matched" $pass_count]

    if {[llength $mismatches] > 0} {
        puts ""
        puts "Mismatched registers:"
        foreach m $mismatches {
            lassign $m name addr exp act
            puts [format "  %-12s @ 0x%02X : expected 0x%02X, got 0x%02X" $name $addr $exp $act]
        }
    }

    puts ""
    if {$i2c_done_val && [llength $mismatches] == 0} {
        puts "RESULT: PASS — SCCB two-wire communication verified on SIOC/SIOD pins."
        puts "        All 16 OV7670 registers match the programmed configuration."
        puts "        (Analog rise-time margin not covered by this digital check.)"
        return 1
    } elseif {!$i2c_done_val} {
        puts "RESULT: FAIL — i2c_done never asserted. SCCB writes did not complete."
        puts "        Check SIOC/SIOD pin assignment, external pull-ups, and OV7670 power."
        return 0
    } else {
        puts "RESULT: FAIL — i2c_done asserted but [llength $mismatches] register(s) mismatch."
        puts "        Partial SCCB success; possible SIOD corruption or wrong device on bus."
        return 0
    }
}

proc print_ref_pixels {} {
    global hw dev

    puts "=== print_ref_pixels (captured reference pixels from camera_interface line 1"
    puts "Shows both byte orderings; one should look scene-plausible (luminance trend)."

    if {![info exists hw] || ![info exists dev]} {
        puts "Not connected; calling connect_live_stream first."
        connect_live_stream
    }

    _close_probe_session
    start_insystem_source_probe -hardware_name $hw -device_name $dev

    set rp01 [_read_probe_if_present 3]
    set rp23 [_read_probe_if_present 4]
    set rp45 [_read_probe_if_present 5]
    set rp67 [_read_probe_if_present 6]

    _close_probe_session

    _require_hex $rp01 "REF01"
    _require_hex $rp23 "REF23"
    _require_hex $rp45 "REF45"
    _require_hex $rp67 "REF67"

    set pairs [list \
        [list rp@x20  $rp01 31 16] \
        [list rp@x60  $rp01 15  0] \
        [list rp@x100 $rp23 31 16] \
        [list rp@x140 $rp23 15  0] \
        [list rp@x180 $rp45 31 16] \
        [list rp@x220 $rp45 15  0] \
        [list rp@x260 $rp67 31 16] \
        [list rp@x300 $rp67 15  0] \
    ]

    puts [format "%-10s  %-6s  %-10s  %-10s  %-14s  %-14s" "Pixel" "X" "Raw(15:0)" "ByteSwap" "R G B Orig(Y)" "R G B Swapped(Y)"]
    puts "----------  ------  ----------  ----------  --------------  ----------------"

    foreach pair $pairs {
        lassign $pair label probe_hex msb lsb
        set probe_val [scan $probe_hex %x]
        set raw [expr {($probe_val >> $lsb) & 0xFFFF}]
        set b0 [expr {($raw >> 8) & 0xFF}]
        set b1 [expr { $raw & 0xFF}]
        set swapped [expr {($b1 << 8) | $b0}]
        set r_orig [expr { ($raw >> 11) & 0x1F}]
        set g_orig [expr { ($raw >>  5) & 0x3F}]
        set b_orig [expr {  $raw & 0x1F}]
        set r_sw   [expr {($swapped >> 11) & 0x1F}]
        set g_sw   [expr {($swapped >>  5) & 0x3F}]
        set b_sw   [expr { $swapped & 0x1F}]
        set lum_orig [expr {($r_orig * 30 + $g_orig * 59 + $b_orig * 11) / 100}]
        set lum_sw   [expr {($r_sw   * 30 + $g_sw   * 59 + $b_sw   * 11) / 100}]
        set xcoord [string range $label 2 end]
        puts [format "%-10s  x%-5s  0x%04X      0x%04X      %2d %2d %2d (%3d)   %2d %2d %2d (%3d)" \
                  $label $xcoord \
                  $raw $swapped \
                  $r_orig $g_orig $b_orig $lum_orig \
                  $r_sw   $g_sw   $b_sw   $lum_sw]
    }

    puts ""
    puts "Interpretation: scan across pixels x20 -> x300 (left-to-right)."
    puts "  Correct byte order shows a smooth luminance trend from left to right across the scene."
    puts "  Wrong byte order gives wildly fluctuating Y values and incorrect primary colours."
}
