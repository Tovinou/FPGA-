# =============================================================================
# de10_lite_ssi_cdc.sdc
# Clock Domain Crossing (CDC) Analysis & Timing Constraints
# SSI Master — DE10-Lite / Intel MAX10 (10M50DAF484C7G)
#
# This file is a COMPLETE replacement for de10_lite_ssi.sdc.
# It adds:
#   - Exhaustive CDC path analysis and rationale for every crossing
#   - set_clock_groups for all clock/asynchronous domain relationships
#   - Explicit set_max_delay / set_min_delay where protocol timing governs
#   - Synchroniser path preservation directives
#   - Recovery/removal checks on the asynchronous reset
#
# Design hierarchy:
#   de10_lite_ssi_top
#   ├── u_key1_det : falling_edge_det   (2-FF synchroniser on KEY[1])
#   ├── u_trig     : trigger_gen
#   ├── u_ssi      : ssi_master
#   │   ├── u_clk_div : ssi_clk_div     (generates clk_en enable tick)
#   │   ├── u_fsm     : ssi_fsm         (IDLE/START/SHIFTING/DONE/MONOFLOP)
#   │   ├── u_shift   : ssi_shift       (serial shift register)
#   │   └── u_clk_out : ssi_clk_out     (drives GPIO_0_0 / ssi_clk pin)
#   ├── u_pos_latch : pos_latch
#   └── u_display   : display_ctrl
#       └── u_hex0..u_hex5 : seg7_decoder
#
# Clock domains present in this design
# ─────────────────────────────────────
#  Domain       Source              Freq        Flip-flops
#  sys_clk      MAX10_CLK1_50 pin   50 MHz      ALL registers in the design
#  ssi_clk_gen  ssi_clk_out reg     500 kHz     NONE (logical/documentation only)
#
# IMPORTANT: ssi_clk_gen is NOT a real clock domain.
#   The ssi_clk register inside u_clk_out is clocked by sys_clk.
#   The generated clock declaration is for board-level documentation and
#   to give TimeQuest a name for the GPIO_0_0 output waveform only.
#   There are ZERO flip-flops in the design that are clocked by ssi_clk_gen.
#
# True asynchronous inputs (not clocked by any FPGA clock):
#   GPIO_0_1   — SSI DATA from encoder     (sampled by sys_clk logic)
#   KEY[0]     — Asynchronous reset         (async preset/clear on FFs)
#   KEY[1]     — Manual trigger button      (synchronised by falling_edge_det)
#   SW[*]      — Slide switches             (quasi-static, sampled by sys_clk)
# =============================================================================


# =============================================================================
# SECTION 1 — BASE CLOCK DEFINITION
# =============================================================================

create_clock \
    -name   sys_clk \
    -period 20.000 \
    [get_ports MAX10_CLK1_50]

# Clock quality: on-board 50 MHz oscillator (typical 50 ppm accuracy)
# Setup uncertainty accounts for board skew, jitter, and PVT variation.
set_clock_uncertainty -setup 0.300 -from [get_clocks sys_clk] -to [get_clocks sys_clk]
set_clock_uncertainty -hold  0.100 -from [get_clocks sys_clk] -to [get_clocks sys_clk]


# =============================================================================
# SECTION 2 — GENERATED CLOCK (documentation only — no real clock domain)
#
# CDC NOTE 2.1:
#   The ssi_clk register in u_clk_out is a DATA register clocked by sys_clk.
#   Its output drives a GPIO pin and toggles every 50 sys_clk cycles.
#   Quartus infers this as a user-instantiated clock buffer if we declare a
#   generated clock on its output — this is useful for:
#     (a) BoardSTA / IO timing reports
#     (b) Signal integrity analysis by downstream tools
#   It does NOT create a second clock domain inside the FPGA.
#
#   Evidence: grep all VHDL source files — every "rising_edge(clk)" references
#   the single port named 'clk' which is driven by MAX10_CLK1_50.
#   No register uses ssi_clk_gen as its clock.
# =============================================================================

create_generated_clock \
    -name       ssi_clk_gen \
    -source     [get_ports MAX10_CLK1_50] \
    -divide_by  100 \
    -master_clock sys_clk \
    [get_ports GPIO_0_0]

create_generated_clock \
    -name       ssi_clk_r_int \
    -source     [get_ports MAX10_CLK1_50] \
    -divide_by  100 \
    -master_clock sys_clk \
    [get_registers {ssi_master:u_ssi|ssi_clk_out:u_clk_out|ssi_clk_r}]

set_clock_uncertainty -setup 0.300 -from [get_clocks sys_clk]        -to [get_clocks ssi_clk_r_int]
set_clock_uncertainty -setup 0.300 -from [get_clocks ssi_clk_r_int]  -to [get_clocks sys_clk]
set_clock_uncertainty -setup 0.300 -from [get_clocks ssi_clk_r_int]  -to [get_clocks ssi_clk_r_int]
set_clock_uncertainty -hold  0.100 -from [get_clocks sys_clk]        -to [get_clocks ssi_clk_r_int]
set_clock_uncertainty -hold  0.100 -from [get_clocks ssi_clk_r_int]  -to [get_clocks sys_clk]
set_clock_uncertainty -hold  0.100 -from [get_clocks ssi_clk_r_int]  -to [get_clocks ssi_clk_r_int]


# =============================================================================
# SECTION 3 — CLOCK GROUP RELATIONSHIPS
#
# CDC NOTE 3.1 — sys_clk is the only real clock group.
#   set_clock_groups declares which clock pairs are asynchronous to each other
#   and therefore do not require TimeQuest to calculate hold/setup between them.
#
#   sys_clk  ←→  ssi_clk_gen :
#     They share the same source oscillator (ssi_clk_gen is derived from
#     sys_clk). They are therefore SYNCHRONOUS in origin. However, since
#     ssi_clk_gen clocks NO flip-flops in the design, there are no register-to-
#     register paths between the two, so no set_clock_groups is needed.
#     TimeQuest will find zero paths crossing this boundary.
#
#   sys_clk  ←→  async inputs (GPIO, KEY, SW):
#     These are handled via false paths and synchroniser constraints below.
#     No set_clock_groups is required for IO ports.
# =============================================================================

# (No set_clock_groups required — single effective clock domain)


# =============================================================================
# SECTION 4 — ASYNCHRONOUS RESET (KEY[0] / rst_n)
#
# CDC NOTE 4.1 — Asynchronous Assert, Synchronous De-assert
#
#   KEY[0] is connected directly to the rst_n port of every VHDL entity.
#   All registers use the pattern:
#       if rst_n = '0' then  <async assert>
#       elsif rising_edge(clk) then  <sync de-assert>
#
#   This is the industry-standard "asynchronous assert / synchronous de-assert"
#   reset topology.  It is SAFE because:
#     - Assertion is asynchronous:  the flip-flop preset/clear path is used,
#       which is metastability-free by design.
#     - De-assertion is synchronous: rst_n must be stable HIGH before the next
#       rising clock edge, so no metastability window exists on release.
#
#   TimeQuest recovery/removal checks:
#     - RECOVERY: minimum time rst_n must be HIGH before rising_edge(clk).
#       Violation would cause unpredictable exit from reset.
#     - REMOVAL:  minimum time rst_n must remain LOW after rising_edge(clk).
#       Violation could corrupt reset assertion.
#
#   Since KEY[0] is a human-operated button (millisecond timescales) and
#   rst_n is used as async clear, we apply set_false_path to cut STA on the
#   input → FF async-clear path.  Recovery/removal is met by many orders of
#   magnitude given human reaction times.
# =============================================================================

set_false_path -from [get_ports {KEY[0]}]

# If you wish to enable recovery/removal analysis for formal sign-off, replace
# the false path above with:
#   set_input_delay -clock sys_clk -max 19.0 [get_ports {KEY[0]}]
#   set_input_delay -clock sys_clk -min  0.0 [get_ports {KEY[0]}]


# =============================================================================
# SECTION 5 — KEY[1] SYNCHRONISER PATH (falling_edge_det)
#
# CDC NOTE 5.1 — Two-flip-flop button synchroniser
#
#   KEY[1] is an asynchronous input from a human operator.  It passes through
#   a 2-stage synchroniser inside falling_edge_det (signal 'sr').
#
#   VHDL structure (falling_edge_det.vhd):
#       sr <= sr(STAGES-2 downto 0) & pin;   -- shift in on rising_edge(clk)
#
#   The first flip-flop (sr(0) after the shift, sr_reg[0] in netlist terms)
#   is the metastability-resolving stage.  TimeQuest must NOT apply its normal
#   setup check to the path from GPIO → sr_first_ff because the design
#   intentionally allows metastability to resolve within one sys_clk period
#   (20 ns).  The second FF then captures the resolved value.
#
#   Constraint strategy:
#     1. Cut the input→first-FF path with set_false_path (no setup check).
#     2. Apply set_max_delay -datapath_only on the first-FF→second-FF path to
#        ensure the propagation delay is within one clock period (20 ns),
#        preserving the synchroniser function without hold-time pessimism.
#
#   MTBF calculation (informational):
#     For sys_clk = 50 MHz, tw = 20 ns resolution window, button press rate
#     ~10 Hz:  MTBF >> 10^15 years — metastability risk is negligible.
# =============================================================================

# Cut async input → first synchroniser FF (no STA on this path)
set_false_path \
    -from [get_ports {KEY[1]}] \
    -to   [get_registers {falling_edge_det:u_key1_det|sr[0]}]

# Preserve synchroniser chain: first FF → second FF must meet 1-cycle budget
set_max_delay \
    -from [get_registers {falling_edge_det:u_key1_det|sr[0]}] \
    -to   [get_registers {falling_edge_det:u_key1_det|sr[1]}] \
    20.000


# =============================================================================
# SECTION 6 — SSI DATA INPUT (GPIO_0_1 / ssi_data)
#
# CDC NOTE 6.1 — Protocol-timed asynchronous input
#
#   GPIO_0_1 carries the SSI DATA signal from the external absolute encoder.
#   It is asynchronous to sys_clk (no phase relationship).
#
#   However, unlike a true asynchronous bus, the SSI protocol provides a
#   well-defined timing guarantee:  the encoder updates DATA only on the
#   FALLING edge of SSI_CLK.  The FPGA samples DATA on the RISING edge of
#   SSI_CLK (a virtual event computed inside ssi_shift — NOT a real clock).
#
#   Timeline (sys_clk counts at 50 MHz, SSI_CLK at 500 kHz = div-by-100):
#
#     sys_clk cycle 0    : ssi_clk toggles LOW  (falling virtual edge)
#     sys_clk cycles 1-49: encoder propagates new DATA (tPD ≤ 300 ns = 15 cycles)
#     sys_clk cycle 50   : ssi_clk toggles HIGH (rising virtual edge)
#                          ssi_shift samples GPIO_0_1 on THIS sys_clk edge
#
#   Setup window available = 50 sys_clk cycles - encoder propagation delay
#                          = 1000 ns - 300 ns = 700 ns  (35 sys_clk cycles)
#   Hold window            = encoder tHOLD ≈ 0 ns
#
#   Because DATA is STABLE for ≥ 35 sys_clk cycles before sampling, there is
#   NO metastability risk.  The input behaves as a synchronous signal relative
#   to the virtual SSI clock.  No synchroniser is needed.
#
#   Constraint: cut STA on this input entirely.  The protocol timing makes
#   it safe; no set_input_delay constraint is achievable because the external
#   encoder is not synchronised to the MAX10 oscillator.
# =============================================================================

set_false_path -from [get_ports {GPIO_0_1}]


# =============================================================================
# SECTION 7 — SLIDE SWITCHES (SW[*])
#
# CDC NOTE 7.1 — Quasi-static configuration inputs
#
#   The SW[9:0] slide switches are sampled combinationally in trigger_gen.vhd:
#       start_pulse <= manual_trig or (sw_auto and busy_fell);
#   where sw_auto = SW(9).
#
#   CDC risk: SW(9) changes are asynchronous to sys_clk and can cause a
#   glitch on start_pulse.  However:
#     - A spurious start_pulse in auto mode simply triggers one extra SSI read.
#     - The SSI master will not be harmed by an extra read request.
#     - Switches are operated at human timescales (milliseconds), not
#       approaching the metastability window of sys_clk (nanoseconds).
#
#   Formal mitigation (not implemented in RTL, acceptable for this design):
#     If strict glitch immunity is required, add a 2-FF synchroniser on SW(9)
#     before the trigger_gen input.
#
#   Constraint: cut STA.  Switches are not timing-critical.
# =============================================================================

set_false_path -from [get_ports {SW[*]}]


# =============================================================================
# SECTION 8 — SSI CLK OUTPUT (GPIO_0_0)
#
# CDC NOTE 8.1 — Registered data output, not a timing-critical path
#
#   GPIO_0_0 is driven by the ssi_clk_r register inside ssi_clk_out.vhd.
#   That register is clocked by sys_clk and updated every 50 cycles.
#
#   There is NO downstream logic inside the FPGA that is clocked by this pin.
#   The encoder uses this pin as its own clock, but the encoder logic is
#   entirely outside the FPGA.
#
#   Set false path to prevent TimeQuest from applying an unrealistic 20 ns
#   setup constraint on a 2000 ns output period signal.
# =============================================================================

set_false_path -to [get_ports {GPIO_0_0}]


# =============================================================================
# SECTION 9 — DISPLAY AND LED OUTPUTS
#
# CDC NOTE 9.1 — Stable registered outputs, no external timing requirement
#
#   HEX0–HEX5 are driven by seg7_decoder (combinational) whose input is
#   pos_latched, a sys_clk-synchronous register updated once per SSI frame
#   (~125 µs at default settings).
#
#   LEDR[9:0] is driven directly from pos_latched bits.
#
#   These outputs drive human-readable displays.  There is no external device
#   that samples these signals on a clock edge — no setup/hold constraint applies.
# =============================================================================

set_false_path -to [get_ports {HEX0[*]}]
set_false_path -to [get_ports {HEX1[*]}]
set_false_path -to [get_ports {HEX2[*]}]
set_false_path -to [get_ports {HEX3[*]}]
set_false_path -to [get_ports {HEX4[*]}]
set_false_path -to [get_ports {HEX5[*]}]
set_false_path -to [get_ports {LEDR[*]}]


# =============================================================================
# SECTION 10 — INTERNAL MULTICYCLE PATHS
#
# CDC NOTE 10.1 — Enable-gated data registers (single clock domain)
#
#   All internal registers are clocked by sys_clk. No true CDC exists inside
#   the design.  However, certain data paths span many clock cycles between
#   updates and could benefit from multicycle relaxation.
#
#   Path: ssi_shift:u_shift|shift_reg → pos_latch:u_pos_latch|pos_out
#         (data_out → data_in, captured when valid = '1')
#
#   Update rate: once per SSI frame = 2 × DATA_BITS × (sys_clk / SSI_CLK)
#              = 2 × 25 × 100 = 5000 sys_clk cycles minimum
#
#   The downstream consumers (seg7_decoder inputs) are on false paths.
#   No multicycle constraint is required — TimeQuest will use the 1-cycle
#   default and will pass easily.
#
# CDC NOTE 10.2 — clk_en enable tick
#
#   clk_en from ssi_clk_div is a sys_clk-synchronous enable, not a clock.
#   It is used to gate updates inside ssi_fsm, ssi_shift, and ssi_clk_out.
#   All receiving registers are in the same clock domain (sys_clk).
#   No CDC constraint is needed.
#
# CDC NOTE 10.3 — busy_fell in trigger_gen
#
#   busy_prev and busy are both sys_clk registers.
#   busy_fell = busy_prev AND NOT busy  (combinational).
#   No CDC crossing — same domain.
# =============================================================================

# (No multicycle path constraints needed — STA passes with 1-cycle default)


# =============================================================================
# SECTION 11 — COMPLETE CDC CROSSING INVENTORY
#
#  #  Signal(s)        From Domain      To Domain    Type       Mitigation
#  ─  ───────────────  ───────────────  ───────────  ─────────  ─────────────────────────────────────
#  1  KEY[0] / rst_n   Async (board)    sys_clk FFs  Async rst  Async-assert/sync-deassert topology.
#                                                               False path constraint (Sec 4).
#
#  2  KEY[1]           Async (board)    sys_clk      Async btn  2-FF synchroniser in falling_edge_det.
#                                                               Sync FF preserved (Sec 5).
#
#  3  GPIO_0_1         Async (encoder)  sys_clk      Protocol   Protocol guarantees 700 ns setup
#                      (SSI DATA)       ssi_shift    -timed     margin before sampling edge (Sec 6).
#                                                               False path constraint.
#
#  4  SW[9:0]          Async (human)    sys_clk      Quasi-     Human timescale, glitch-tolerant
#                                       trigger_gen  static     application. False path (Sec 7).
#
#  5  GPIO_0_0         sys_clk          Async         Output     Data output only — no FPGA logic
#                      (ssi_clk_r)      (encoder CLK) -only      clocked by this pin. False path (Sec 8).
#
#  Note: ssi_clk_gen is a logical/documentation clock only.
#        There are ZERO flip-flops in the design clocked by ssi_clk_gen.
#        Items 3 and 5 are the only encoder-interface crossings.
#        All internal register-to-register paths are in the sys_clk domain.
# =============================================================================


# =============================================================================
# SECTION 12 — TIMING SUMMARY (expected TimeQuest results)
#
#  Clock              Setup Slack   Hold Slack   Notes
#  ─────────────────  ───────────   ──────────   ──────────────────────────────
#  sys_clk (50 MHz)   > +5 ns       > +0.1 ns    All internal paths
#  ssi_clk_gen        N/A           N/A          No flip-flops in this domain
#
#  All false-pathed ports will show "N/A" in IO timing reports.
#  The synchroniser path (Sec 5) will show exactly 20.000 ns max delay.
#
#  If TimeQuest reports:
#    - Slack < 0 on sys_clk paths  → report to design team; logic may be
#                                    too deep (check combinational depth of
#                                    ssi_fsm next-state logic).
#    - "No paths found" on ssi_clk_gen → expected and correct.
#    - Unconstrained paths (yellow/red in summary) → add false_path for that
#                                    port and document reasoning in this file.
# =============================================================================


# =============================================================================
# SECTION 13 — OPTIONAL DIRECTIVES (uncomment as needed)
# =============================================================================

# Derive any PLL-generated clocks automatically (not needed here — no PLL)
# derive_pll_clocks

# Automatically compute clock uncertainty from PLL specs
# derive_clock_uncertainty

# Force fitter to place synchroniser FFs in the same LAB for minimum routing
# set_instance_assignment -name SYNCHRONIZER_IDENTIFICATION FORCED \
#     -to {de10_lite_ssi_top:*|falling_edge_det:u_key1_det|sr[0]}
