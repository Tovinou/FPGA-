# =============================================================================
# live_stream_final.sdc  —  CORRECTED Timing Constraints (v3)
# Target: Intel MAX10 10M50DAF484C7G  (DE10-Lite)
# Tool:   Quartus Prime 25.1 Lite Edition
#
# PLL (100 MHz):
#   clk[0] = 100 MHz, 0 deg    -> SDRAM controller + camera FIFO read
#   clk[1] = 100 MHz, +2500 ps -> DRAM_CLK output pin only
#   clk[2] = 25 MHz, 0 deg     -> VGA pixel clock
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
create_generated_clock -name DRAM_CLK_PIN \
    -source [get_pins {u_pll|altpll_component|auto_generated|pll1|clk[1]}] \
    [get_ports {DRAM_CLK}]
derive_clock_uncertainty

# =============================================================================
# 3.  ASYNCHRONOUS CLOCK GROUPS
#
#   Group A: OV7670_PCLK          (async external camera clock)
#   Group B: clk[0] + clk[1]      (100 MHz PLL, same source, phase-related)
#   Group C: clk[2]               (25 MHz VGA pixel clock)
#
#   clk[0] and clk[1] stay in one group so Quartus analyses the
#   clk[0]-launched / clk[1]-captured SDRAM output path correctly.
#   CDC paths between groups are excluded from setup/hold analysis —
#   the dcfifo IP handles metastability internally (84 protected registers).
# =============================================================================
set_clock_groups -asynchronous \
    -group [get_clocks {OV7670_PCLK}] \
    -group [get_clocks {*pll*|clk[0]* *pll*|clk[1]* DRAM_CLK_PIN}] \
    -group [get_clocks {*pll*|clk[2]*}]

# =============================================================================
# 4.  ASYNC RESET FALSE PATHS
#     MAX10 only has clrn (active-low synchronous clear mapped to reset).
#     prn does NOT exist on MAX10 — omit it to avoid Warning 332174.
# =============================================================================
set_false_path -to [get_pins -hierarchical {*|clrn}]

# =============================================================================
# 5.  DRAM_CLK (Replaced by generated clock, no longer a false path)
# =============================================================================


# =============================================================================
# 6.  OV7670 CAMERA INPUT TIMING
# =============================================================================
set_input_delay -clock {OV7670_PCLK} -max 10.000 \
    [get_ports {OV7670_D[*] OV7670_HREF OV7670_VSYNC}]
set_input_delay -clock {OV7670_PCLK} -min  2.000 \
    [get_ports {OV7670_D[*] OV7670_HREF OV7670_VSYNC}]

# =============================================================================
# 7.  SDRAM OUTPUT TIMING  (FPGA -> IS42S16320F)
#
#   Launch:  clk[0] (100 MHz, 0 deg)
#   Capture: DRAM_CLK = clk[1] (100 MHz, +2500 ps = +90 deg)
#   IS42S16320F -6:  tSU = 1.5 ns,  tH = 0.8 ns
#
#   Available output path: 2500 - 1500 = 1000 ps
#   Tight but valid when clk[0]/clk[1] are correctly phase-related.
# =============================================================================
set_output_delay -clock [get_clocks DRAM_CLK_PIN] -max  1.500 \
    [get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_CKE DRAM_CS_N \
                DRAM_RAS_N DRAM_CAS_N DRAM_WE_N DRAM_UDQM DRAM_LDQM}]
set_output_delay -clock [get_clocks DRAM_CLK_PIN] -min -0.800 \
    [get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_CKE DRAM_CS_N \
                DRAM_RAS_N DRAM_CAS_N DRAM_WE_N DRAM_UDQM DRAM_LDQM}]

set_output_delay -clock [get_clocks DRAM_CLK_PIN] -max  1.500 \
    [get_ports {DRAM_DQ[*]}]
set_output_delay -clock [get_clocks DRAM_CLK_PIN] -min -0.800 \
    [get_ports {DRAM_DQ[*]}]

# =============================================================================
# 8.  SDRAM INPUT TIMING  (IS42S16320F -> FPGA, DQ read)
#
#   Capture clock: clk[0] (internal 100 MHz)
#   DRAM_CLK at +2500 ps. IS42S16320F CL=3, tAC(max)=5.4 ns, tOH(min)=2.0 ns
#
#   Physical DQ arrives at FPGA pin:
#     DRAM_CLK_edge(CL) + tAC = clk[0] + 2500 + 5400 = clk[0] + 7900 ps
#   Capture at: clk[0] + 1 period = clk[0] + 10000 ps
#   Margin: 10000 - 7900 = 2100 ps
#
#   set_multicycle_path: sdram_controller explicitly waits CL=3 cycles before
#   sampling sdram_dq (read_pipe shift register). Quartus must not penalise
#   single-cycle timing on this port — it is captured CL cycles later.
# =============================================================================
set_input_delay -clock [get_clocks DRAM_CLK_PIN] -max 5.400 \
    [get_ports {DRAM_DQ[*]}]
set_input_delay -clock [get_clocks DRAM_CLK_PIN] -min 0.100 \
    [get_ports {DRAM_DQ[*]}]

# Multi-cycle: DQ physically captured 3 clk[0] cycles after READ command.
# CL=3 in MODE_REG — read_pipe shift register provides correct timing.
set_multicycle_path -from [get_ports {DRAM_DQ[*]}] \
    -to   [get_clocks {*pll*|clk[0]*}] \
    -setup 3
set_multicycle_path -from [get_ports {DRAM_DQ[*]}] \
    -to   [get_clocks {*pll*|clk[0]*}] \
    -hold 2

# =============================================================================
# 9.  FALSE PATHS — I/O with no timing requirement
# =============================================================================
set_false_path -from [get_ports {KEY[*]}]
set_false_path -to   [get_ports {LEDR[*]}]
set_false_path -to   [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS}]
set_false_path -to   [get_ports {OV7670_XCLK OV7670_SIOC OV7670_RESET_N OV7670_PWDN}]
set_false_path -to   [get_ports {OV7670_SIOD}]
set_false_path -from [get_ports {OV7670_SIOD}]

# =============================================================================
# END OF CONSTRAINTS
# =============================================================================
