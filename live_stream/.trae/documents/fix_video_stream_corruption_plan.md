# Fix Video Stream Corruption Implementation Plan

## Repository Research

### Symptom Analysis
The captured image shows three distinct failure modes, all present simultaneously:
1. **Salt-and-pepper pixel noise (50% of pixels)**: Individual pixel blocks are filled with stale/wrong values at fixed checkerboard positions.
2. **Severe color corruption (magenta center, yellow edges)**: Entire color plane mapping is inverted, consistent with reversed RGB565 endianness.
3. **Concentric-ring / gradient distortion**: Frame content appears rotated or mapped to wrong coordinates, caused by per-pixel misalignment accumulating across lines.

### Root Cause Findings (verified in RTL)

#### Finding A – Stale pixel display (CRITICAL, vga_interface.vhd:209-221)
The `pixel_next` variable is only conditionally assigned inside nested `if/elsif` branches. Any cycle that does not match a branch keeps the **previous pixel's value**, yielding a systematic checkerboard of wrong pixels:

| VGA position (h,v) | Current code does: | Correct behaviour: |
|---|---|---|
| (even_h, even_v) | `pixel_next` NOT assigned → retains previous block | Display newly-fetched FIFO pixel (but fetch issued only on previous cycle, so need 1-cycle align) |
| (odd_h, even_v) | `rd_en_q='1'` → `pixel_next = fifo_rd_data` ✓ | Display newly-fetched pixel ✓ |
| (even_h, odd_v) | NOT assigned → retains previous | Replay from line_buf |
| (odd_h, odd_v) | `line_buf(disp_idx)` → displayed ✓ | Replay from line_buf ✓ |

Net effect: exactly half the displayed 2×2 blocks are the WRONG neighbour pixel.

#### Finding B – RGB565 byte order inverted by default (HIGH)
- OV7670 [i2c_top.vhd line 79](file:///c:/Jensen/projects/fpga/live_stream/camera_subsystem/i2c_top.vhd#L79): `TSLB = 0x0C` (bit 3 set = OV outputs RGB565 **low byte first**).
- [stream_top.vhd](file:///c:/Jensen/projects/fpga/live_stream/stream_top.vhd): `SW(7)` → `swap_bytes`, default `SW="0000000000"` so `swap_bytes='0'`.
- [camera_interface.vhd lines 289-295](file:///c:/Jensen/projects/fpga/live_stream/camera_subsystem/camera_interface.vhd#L289-L295): with `swap_bytes='0'`, first byte → MSB position, second byte → LSB position.
- Result: `pixel_word = {G[1:0]B[4:0], R[4:0]G[5:2]}` instead of correct `{R G B}`. Every color channel is mangled, producing the dominant magenta + yellow field in the image.

#### Finding C – FIFO reset race per VSYNC (MEDIUM, vga_subsystem.vhd:187)
`fifo_rst_n <= rst_n and vga_vsync;` asserts async-FIFO read-side reset for the full VSYNC-active pulse every frame. Write-side reset arrives two 100-MHz cycles later via sync. If the SDRAM reader issues pixels while either side is still coming out of reset, the first N pixels of each frame are silently dropped, causing a systematic horizontal offset / slant that accumulates to the concentric-ring appearance.

#### Finding D – VGA DAC uses active_d (MEDIUM, vga_interface.vhd:316-323)
The DAC mux gates on registered `active_d` rather than `active`. Combined with the unregistered `pixel_next` value on half the cycles, the first column of every line and blanking transitions show extra wrong-channel bits.

### Constraints
- Do not change the debug switch positions (SW(0)…SW(9) must remain available as manual overrides); we fix the DEFAULT behaviour.
- Do not change OV7670 I²C register values that are already being verified by the new `check_camera_sccb` command (TSLB is included in the 16-register check, so TSLB is fixed at 0x0C → we must fix the FPGA side byte assembly to match).

## Files and Modules

1. **[vga_interface.vhd](file:///c:/Jensen/projects/fpga/live_stream/vga_subsystem/vga_interface.vhd)**
   - Rewrite the pixel_next assignment in `p_vga_sync` so every active-cycle path assigns a defined value.
   - Use a `src_pixel` registered signal that always carries the correct pixel for the current display position based on whether it's fetch-row or replay-row, and whether the current h_count is the fetch (even) or display (odd) sub-cycle.
   - Align line_buf write → read timing so that (even_h, odd_v) also displays the buffered value, not a stale neighbour.
   - Gate DAC output on the same `active` qualifier used for the pixel register, keeping one output latency so timing is clean.

2. **[stream_top.vhd](file:///c:/Jensen/projects/fpga/live_stream/stream_top.vhd)**
   - Override the default `swap_bytes` tie-off: force `swap_bytes_int = '1'` (correct for TSLB=0x0C) at the top-level switch assignment, while still letting SW(7) invert it for debug. Or equivalently, OR a constant with SW(7) so default power-on = correct byte order.
   - Keep SW(7) pin connected but invert the logic so "switch UP = override to wrong order". Alternatively, leave switch semantics (swap_bytes = SW(7)) but change the default in the switch vector comment and add an explicit tie-off that swaps by default. Simplest correct change: `swap_bytes_int <= '1';` (ignore SW(7) default-on; keep SW(7) for forced no-swap only if needed, but the cleanest is to set `cam_swap_bytes <= not SW(7)` so SW(7) OFF = swap ON = correct default).

3. **[vga_subsystem.vhd](file:///c:/Jensen/projects/fpga/live_stream/vga_subsystem/vga_subsystem.vhd)**
   - Remove the per-VSYNC async FIFO reset; gate `fifo_rst_n` only on the external `rst_n`, not on `vga_vsync`. Rely on SDRAM-reader restart + FIFO prefill gating to keep alignment. If a one-time startup flush is needed, pulse reset only once after PLL lock, not every 16.7 ms.
   - Mirror the same change on the write-side `fifo_rst_n_wr`.

4. **[camera_debug.tcl](file:///c:/Jensen/projects/fpga/live_stream/camera_debug.tcl)**
   - Add a small `print_pixel_health` helper that reads the REF pixel probes and prints expected vs actual byte ordering (e.g., whether ref_pixel0 shows a reasonable luminance-sorted value after byte-swap vs the unsorted value) so you can confirm Finding B with the TCL console after running `check_camera_sccb`. This is diagnostics, not functional.

## Implementation Steps

### Step 1 — Correct RGB565 byte order at top level (stream_top.vhd)
Locate the `cam_swap_bytes <= SW(7);` line. Change it to:
```vhdl
cam_swap_bytes <= not SW(7);  -- default (SW7 down = 0) -> swap ON, correct for TSLB=0x0C
```
Update the nearby comment block documenting SW mapping to reflect that SW(7), when UP, DISABLES byte swap (for manual debug only).

### Step 2 — Rewrite vga_interface pixel pipeline (vga_interface.vhd)
Replace the inner `if active = '1'` block that assigns `pixel_next` with logic structured as follows (keep the rest of the process — line_buf writes, reference probes, underflow counting — unchanged in structure):

- Register `src_pixel_q : std_logic_vector(15 downto 0)` (new signal), loaded on every active clock.
- Conceptually, for the 2×2 output block at logical (src_x, src_y):
  - `pclk_cycle (h=2x,   v=2y  )`: issue rd_en_int; `src_pixel_q` holds from previous block; display `src_pixel_q`.
  - `pclk_cycle (h=2x+1, v=2y  )`: `rd_en_q='1'`; latch `fifo_rd_data` into `src_pixel_q` AND write `line_buf[src_x]`; display new `src_pixel_q`.
  - `pclk_cycle (h=2x,   v=2y+1)`: read `line_buf[src_x]` (stored on pass above) into `src_pixel_q`; display it.
  - `pclk_cycle (h=2x+1, v=2y+1)`: re-display `src_pixel_q` (holds value from line_buf).
- Key fix: **every active cycle assigns src_pixel_q**, no implicit hold.
- `pixel` output register remains as the final output pipe stage; assign `pixel <= src_pixel_q;` unconditionally in the active branch.
- DAC output continues using the registered `pixel` signal, and gates on registered `active_d` (keep that — just make sure `pixel` actually carries correct data in every quadrant).

### Step 3 — Remove per-frame VSYNC FIFO reset (vga_subsystem.vhd)
Lines 187 and 199:
```vhdl
-- fifo_rst_n <= rst_n and vga_vsync;             -- OLD, per-frame, buggy
fifo_rst_n <= rst_n;                              -- NEW, reset only at system start
-- fifo_rst_n_wr <= rst_n and vsync_sync_wr2;      -- OLD
fifo_rst_n_wr <= rst_n;                            -- NEW
```
Comment out the vsync-gated reset; leave the existing `p_read_start` arm/disarm FSM in place because the FIFO prefill + `read_start_ready @ usedw>=320` guard is already sufficient to start a frame with the right source pixel at (0,0).

### Step 4 — Add pixel-order sanity check in TCL (camera_debug.tcl)
After `check_camera_sccb`, add a short helper proc `print_ref_pixels` that:
- Opens ISSP, reads probes 3, 4, 5, 6 (`ref_pixels01_dbg`..`ref_pixels67_dbg`) via `read_instance_data`.
- For each 16-bit ref pixel, prints: raw hex, and both byte orders (byte0<<8|byte1 vs byte1<<8|byte0), so the user can visually confirm which byte ordering yields values with realistic luminance (monotonically rising / scene-appropriate).
- This does not change hardware; it lets the user confirm Step 1 had the desired effect without re-running synthesis.

## Dependencies and Considerations

- **TSLB=0x0C constraint**: Because the newly-added `check_camera_sccb` verifies exact match on TSLB=0x0C, the OV register side MUST NOT change. All byte-order fixes live on the FPGA input side only.
- **Switch compatibility**: SW(7) will now, in its default down position, yield correct capture; the user retains the ability to flip SW(7) UP to deliberately disable the swap and reproduce the "before" image (useful for A/B comparison on real hardware).
- **Timing closure**: Step 2 adds logic to the critical VGA output path. The new combinational branches (`v_count(0)=0` vs `=1` and `h_count(0)=0` vs `=1`) fan out to a 16-bit MUX before registering; that's the same depth as the existing conditional hold, so worst-case slack should not regress. Run `quartus_sta` flow as normal; if slack goes negative, register `src_pixel_q` one stage earlier and add a single-pixel delay to `rd_en_q` match.
- **FIFO prefill threshold**: With the per-frame reset removed in Step 3, `START_FILL_LEVEL = 320` (320 words = one camera row buffered) still ensures the SDRAM reader has emitted at least one burst before the VGA starts row 0; no change needed.
- **Underflow counter**: stays untouched; after Step 2, any still-incrementing underflow means the SDRAM reader can't keep up and that is a genuine diagnostic signal, not a pixel pipeline artifact.

## Validation

1. **TCL-side verification first (no rebuild)**:
   - Run `check_camera_sccb` → must still report PASS (16/16 registers unchanged, since Step 1 only touches FPGA byte assembly, not OV registers).
   - Run new `print_ref_pixels` → compare byte-swap vs non-swap hex on all 8 reference pixels; the non-swapped values should look random while the swapped values should show plausible luminance ordering per the target scene.

2. **Synthesise and program image with Steps 1-3 applied**:
   - **SW(0)=1, all other SW=down (default)**: VGA test bars (8 vertical bars, each pure colour) must be correctly ordered and sharp-edged. This isolates vga_interface fix (Step 2) without relying on camera.
   - **SW(0)=0, SW(7)=down (default, new behaviour)**: Displayed image must be a recognisable rendition of the scene pointed at by the camera. Colors must be approximately correct (skin tones pink/peach, green foliage green, sky blue). No checkerboard salt-and-pepper. Concentric rings must be gone.
   - **SW(0)=0, SW(7)=up (override)**: Intentional re-creation of the user's "before" picture — confirms the byte-swap override is the actual causal factor for the observed colors.
   - Run `check_camera_inputs 200 25` → should still report all D bits toggling, PCLK/HREF/VSYNC active (Steps 1-3 do not touch camera clock/sync capture path).
   - Run `sample_once` in the TCL console: `lines=240 pix_div256=300 frame_valid=1` (frame geometry preserved, confirming no new write-path corruption was introduced).

3. **Build QA**:
   - `quartus_sh --flow compile stream_top` → passes without new critical warnings on the modified modules.
   - Timing Analyzer → Worst-Case Setup slack for clk_25m stays positive; no new regressions relative to baseline.
   - Power report → no new combinational loops in vga_interface (Step 2 explicitly assigns `src_pixel_q` on every active cycle, so inferred latch is eliminated).

## Risks

| Risk | Mitigation |
|---|---|
| Step 2 refactor accidentally breaks line_buf write timing | Keep `line_buf(to_integer(read_x_q)) <= fifo_rd_data;` inside the existing `if rd_en_q = '1'` block exactly as-is; only change the **display** MUX, not when/what is stored into line_buf. |
| Removing VSYNC FIFO reset (Step 3) lets tail pixels survive across frames | SDRAM reader already restarts from address 0 on every VGA VSYNC at the sdram_interface layer. The prefill guard (`usedw >= 320` then arm once per frame) means reads begin only after the new frame's first burst is present. Worst-case test: cover the camera lens → go from bright to dark scene → must transition fully within ~1 frame (≤ 33 ms). |
| `not SW(7)` breaks user expectation if they ever set SW(7) UP expecting swap | Update the top-level comment block right next to the `SW => ...` pin mapping so the documentation reflects the new polarity. Mention in code review: "SW(7) UP forces NO swap (override/debug); DOWN = default, follows TSLB correctly." |
| Platform-specific: async FIFO behaviour differs across synthesis runs without explicit reset | The dcfifo megafunction has a DEVICE_FAMILY parameter; ensure `asyn_fifo.vhd` (if custom) or the megawizard output already asserts DEVICE_FAMILY="MAX 10". This is baseline, not introduced by the fix. |
