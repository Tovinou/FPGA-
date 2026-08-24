# =============================================================================
# live_stream_clean.sdc  —  Timing constraints (CLEANED)
# Target: Intel MAX10 10M50DAF484C7G  (DE10-Lite)
# Tool:   Quartus Prime 25.1
#
# NOTE: Simplified constraints to focus on actual critical paths.
# Broken multicycle paths removed - they were causing Quartus to ignore constraints.
# =============================================================================

# =============================================================================
# 1.  BASE CLOCKS
# =============================================================================
create_clock -name {MAX10_CLK1_50} -period 20.000 \
    [get_ports {MAX10_CLK1_50}]

create_clock -name {OV7670_PCLK} -period 40.000 \
    [get_ports {OV7670_PCLK}]

# =============================================================================
# 2.  PLL-DERIVED CLOCKS
# =============================================================================
derive_pll_clocks
derive_clock_uncertainty

# =============================================================================
# 3.  ASYNCHRONOUS CLOCK GROUPS
# =============================================================================

# Camera PCLK is asynchronous to all internal PLL clocks
set_clock_groups -asynchronous \
    -group {OV7670_PCLK} \
    -group [get_clocks -nowarn {*pll*|clk[0]* *pll*|clk[1]*}] \
    -group [get_clocks -nowarn {*pll*|clk[2]*}]

# VGA FIFO CDC (clk[0]/clk[1] -> clk[2])
set_clock_groups -asynchronous \
    -group [get_clocks -nowarn {*pll*|clk[0]* *pll*|clk[1]*}] \
    -group [get_clocks -nowarn {*pll*|clk[2]*}]

# =============================================================================
# 4.  ASYNC RESET FALSE PATHS
# =============================================================================
set_false_path -to [get_pins -hierarchical {*|clrn}]

# =============================================================================
# 5.  OV7670 INPUT TIMING
# =============================================================================
set_input_delay -clock {OV7670_PCLK} -max 10.000 \
    [get_ports {OV7670_D[*] OV7670_HREF OV7670_VSYNC}]
set_input_delay -clock {OV7670_PCLK} -min  0.000 \
    [get_ports {OV7670_D[*] OV7670_HREF OV7670_VSYNC}]

# =============================================================================
# 6.  SDRAM OUTPUT TIMING (FPGA -> IS42S16320F)
# =============================================================================
set_output_delay -clock [get_clocks -nowarn {*pll*|clk[1]*}] -max  1.500 \
    [get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_CKE DRAM_CS_N \
                DRAM_RAS_N DRAM_CAS_N DRAM_WE_N DRAM_UDQM DRAM_LDQM}]
set_output_delay -clock [get_clocks -nowarn {*pll*|clk[1]*}] -min -0.800 \
    [get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_CKE DRAM_CS_N \
                DRAM_RAS_N DRAM_CAS_N DRAM_WE_N DRAM_UDQM DRAM_LDQM}]

set_output_delay -clock [get_clocks -nowarn {*pll*|clk[1]*}] -max  1.500 \
    [get_ports {DRAM_DQ[*]}]
set_output_delay -clock [get_clocks -nowarn {*pll*|clk[1]*}] -min -0.800 \
    [get_ports {DRAM_DQ[*]}]

# =============================================================================
# 7.  SDRAM INPUT TIMING (IS42S16320F -> FPGA, DQ read path)
# =============================================================================
set_input_delay -clock [get_clocks -nowarn {*pll*|clk[0]*}] -max 6.000 \
    [get_ports {DRAM_DQ[*]}]
set_input_delay -clock [get_clocks -nowarn {*pll*|clk[0]*}] -min -0.800 \
    [get_ports {DRAM_DQ[*]}]

# =============================================================================
# 8.  FALSE PATHS — Unconstrained pins
# =============================================================================
set_false_path -from [get_ports {KEY[*]}]
set_false_path -to   [get_ports {LEDR[*]}]
set_false_path -to   [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS}]
set_false_path -to   [get_ports {OV7670_XCLK OV7670_SIOC OV7670_RESET_N OV7670_PWDN}]
set_false_path -to   [get_ports {OV7670_SIOD}]
set_false_path -from [get_ports {OV7670_SIOD}]

# =============================================================================
# 9.  CDC FIFO TIMING — Relax async pointer crossings
# =============================================================================

# Camera FIFO: relax CDC constraints to 15 ns (very permissive for async paths)
set_max_delay -from [get_clocks {OV7670_PCLK}] \
              -to   [get_clocks -nowarn {*pll*|clk[0]*}] \
              15.000

set_max_delay -from [get_clocks -nowarn {*pll*|clk[0]*}] \
              -to   [get_clocks {OV7670_PCLK}] \
              40.000

# VGA FIFO: relax CDC constraints
set_max_delay -from [get_clocks -nowarn {*pll*|clk[0]*}] \
              -to   [get_clocks -nowarn {*pll*|clk[2]*}] \
              40.000

set_max_delay -from [get_clocks -nowarn {*pll*|clk[2]*}] \
              -to   [get_clocks -nowarn {*pll*|clk[0]*}] \
              40.000

# =============================================================================
# 10. REDUCE CONSTRAINTS ON STATE MACHINES
# =============================================================================

# I2C/SCCB is slow (100 kHz) - no timing requirement
set_false_path -from [get_ports {OV7670_SIOD}] -to [get_clocks -nowarn {*pll*|*}]
set_false_path -from [get_clocks -nowarn {*pll*|*}] -to [get_ports {OV7670_SIOD}]

# =============================================================================
# END OF CONSTRAINTS
# =============================================================================
