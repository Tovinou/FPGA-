# Fix OV7670 → SDRAM → VGA Live Stream

## Background

The system captures 320×240 RGB565 from an OV7670 camera and streams it to a 640×480 VGA display (each camera pixel upscaled 2×2). The pipeline is:

```
OV7670 PCLK → camera_interface → cam FIFO (512 deep)
                                        ↓
                               sdram_interface
                              /               \
                    SDRAM write             SDRAM read
                   (cam→DRAM)             (DRAM→VGA FIFO)
                                                ↓
                                     vga_interface → monitor
```

Sample-loop data (bypass=1) confirmed the camera is healthy: geometry stable at 240 lines / 76800 px, frame_valid=1, OV7670 config correct. The problems are **all in the SDRAM path and VGA datapath**.

---

## Bugs Found (7 confirmed bugs)

### BUG A — `frame_done` is a level, not an edge-safe pulse (CDC hazard)
**File:** `camera_interface.vhd` lines 348–354  
**Description:** `frame_done` is held HIGH for 64 PCLK cycles (~2.5 µs at 25 MHz). The 2-FF synchroniser in `sdram_subsystem.vhd` samples it cleanly, but the edge detector in `sdram_interface.vhd` at line 255 uses `frame_done_sync = '1' and frame_done_d = '0'` — this correctly fires once on the rising edge. However, the pulse lasts 64 PCLK cycles ≈ 6+ rising edges of the 100 MHz clock, so the edge is seen only once. **This is actually safe.** Not a primary bug, but worth noting.

### BUG B — VGA FIFO reset during active scan (critical)  
**File:** `vga_subsystem.vhd` line 183  
```vhdl
fifo_rst_n <= rst_n and vga_vsync;
```
`vga_vsync` is **active-low** — it goes LOW during the vsync pulse (vc=490 to 492). So this resets the FIFO (holding it in reset, `rd_empty='1'`) during the 2-line vsync pulse. The intent is to flush stale pixels, but the **exact same signal is fed to both write-side and read-side `rst_n`**. The Altera `dcfifo` requires `aclr` to be asserted for at least a few clocks; here it fires for exactly 2 lines × 800 pixels / 4 = ~400 fast-clock cycles. That part is fine. **BUT:** the `read_start_armed` logic in `p_read_start` disarms on the vsync falling edge and only re-arms once `fifo_empty='0'` and `vga_active='0'` while `vga_vsync='1'`. After the reset, the FIFO is empty. The SDRAM FSM needs to fill at least 1 pixel before `read_start_armed` can go high — which may happen during active scan, so VGA starts mid-frame. **This is a timing hazard that creates the partial-frame offset.**

### BUG C — `sdram_interface` SDRAM read never starts (critical — the main bug)
**File:** `sdram_interface.vhd` lines 362–368

The read-issue condition in `ST_FILL_CAM`:
```vhdl
elsif read_frame_valid = '1' and vga_vsync_sync = '1' and
      vga_fifo_full = '0' and rd_ptr < FRAME_PIXELS then
    state <= ST_ISSUE_RD;
```

`vga_vsync_sync = '1'` means VGA is **in active scan** (vsync is high = not in sync pulse). This is correct for normal operation. **But** `vga_fifo_full` comes from `vga_subsystem`, and the `fifo_full` output is `fifo_wr_full` — which is the write-side full flag of the Altera dcfifo. The dcfifo write-side full lags the read-side consumption by several sync cycles. When the FIFO has just been reset and is empty, `fifo_wr_full='0'` — so this part looks correct.

The actual bug: **`read_frame_valid` is never set to `'1'` in practice because the sequence `new_frame_ready → vsync falling edge → read_frame_valid=1` fails.**

Reason: `new_frame_ready` is set on `frame_done` rising edge (line 261). Then it must survive until the **next VGA vsync falling edge** (line 278). The VGA vsync period is 60 Hz = ~16.7 ms. The camera frame period is also ~30 fps = ~33 ms (with the 25 MHz XCLK and CLKRC=0x01 doubling). So `new_frame_ready` is set, waits one vsync — and that should work. 

**The real problem:** `rd_ptr < FRAME_PIXELS` — `FRAME_PIXELS = 76800`. But `rd_ptr` is reset to 0 on *every* vsync falling edge (line 279). After the first successful vsync swap, `read_frame_valid=1`, `rd_ptr=0`. In `ST_FILL_CAM`, the condition `rd_ptr < 76800` is true. **But then the write path takes priority**: `cam_fifo_empty='0'` fires constantly (camera is always writing), so `cam_rd_int` fires, `cam_rd_pending=1`, and the FSM stays in `ST_FILL_CAM` doing camera-to-SDRAM writes. Read bursts only interleave when `cam_rd_pending=0`. Looking at the code flow more carefully:

In `ST_FILL_CAM`, the priority order is:
1. If `cam_rd_pending=1` → process pending camera data (pack burst)  
2. **elif** `read_frame_valid=1 and vga_vsync_sync=1 and vga_fifo_full=0 and rd_ptr < FRAME_PIXELS` → issue read
3. **elif** `cam_fifo_empty='0'` → issue camera read

So reads and writes interleave correctly — IF both conditions 1 and 2 can fire. Let me look at why reads don't happen.

**Real root cause: `vga_fifo_full` is always '1' as seen by the SDRAM interface.**

In `sdram_subsystem.vhd` line 237-244, the `sdram_interface` receives `vga_fifo_full` directly from the subsystem port, which is connected at `stream_top.vhd` line 928:
```vhdl
vga_fifo_full => vga_fifo_full_to_sdram,
```
And `vga_fifo_full_to_sdram` (line 495):
```vhdl
vga_fifo_full_to_sdram <= '1' when bypass_mode = '1' else vga_fifo_full;
```

**In the sample_loop data, bypass=1 (SW(3)=1).** All SCH data was with bypass mode active. The SDRAM FSM sees `vga_fifo_full='1'` always — it never issues reads. This explains `nfr=0`, `st=0`, `rdptr=0`.

**In non-bypass mode (SW(3)=0):** The previous debug notes say "switching back to SW(3)=0 causes the display to freeze." This suggests the SDRAM path has its own bugs too. Let's identify them:

### BUG D — Camera FIFO read data consumed incorrectly (BUG7 comment says fixed, but check)
**File:** `sdram_interface.vhd` lines 312–354  
The comment says BUG7 was fixed: `cam_fifo_rd_en` is issued, then data captured next cycle via `cam_rd_pending`. Looking at the code:
- When `cam_rd_pending=0` and `cam_fifo_empty=0`: fire `cam_rd_int=1`, `cam_rd_pending=1`
- Next cycle: `cam_rd_pending=1` → consume `cam_fifo_rd_data`, pack into `wr_data_latch`

But the Altera dcfifo has `lpm_showahead=OFF` — data appears 1 cycle after `rdreq`. So when `cam_rd_int` goes high and `cam_rd_pending` is set, on the **next** cycle `cam_fifo_rd_data` is valid. This matches. ✓

### BUG E — `frame_done` resets write state mid-burst, losing partial data
**File:** `sdram_interface.vhd` lines 255–271  
When `frame_done` pulses, `wr_ptr <= 0`, `wr_burst_cnt <= 0`, `cam_rd_pending <= 0`. If the FSM was partway through a burst, the partial `wr_data_latch` is abandoned and the write pointer jumps back to 0. This is the intended frame-reset behavior. But it doesn't reset `read_frame_valid` — which remains `'1'` from the previous vsync. So after the new frame starts, `read_frame_valid` is already set from the *old* frame swap, and the SDRAM continues reading from the previous `read_bank` (correct behavior). This is fine — frame_done-triggered write-bank swap is correct.

**However:** `vga_wr_pending` is also cleared to `'0'` on frame_done (line 260). If a VGA FIFO write was in flight (pending but not yet committed), it is silently dropped. Since this happens at the end of a frame (76800 pixels), losing one write is acceptable.

### BUG F — VGA pixel bit-extraction is wrong (major image quality issue)
**File:** `vga_interface.vhd` lines 318–325  

RGB565 format: `[R4:R3:R2:R1:R0 | G5:G4:G3:G2:G1:G0 | B4:B3:B2:B1:B0]` in a 16-bit word `pixel[15:0]`:
- R[4:0] = pixel[15:11]
- G[5:0] = pixel[10:5]  
- B[4:0] = pixel[4:0]

The DE10-Lite VGA connector is 4-bit per channel. Standard mapping (top 4 bits of each channel):
- `vga_r[3:0]` = R[4:1] = `pixel[15:12]`
- `vga_g[3:0]` = G[5:2] = `pixel[10:7]`
- `vga_b[3:0]` = B[4:1] = `pixel[4:1]`

Current code:
```vhdl
vga_r <= pixel(15 downto 12);   -- correct ✓
vga_g <= pixel(10 downto 7);    -- correct ✓
vga_b <= pixel(4  downto 1);    -- correct ✓
```
**This is actually correct.** Not a bug.

### BUG G — `asyn_fifo.vhd` (VGA) missing `wr_usedw` port but called with it
**File:** `vga_subsystem/asyn_fifo.vhd` (different from `camera_subsystem/asyn_fifo.vhd`)

The VGA subsystem's `asyn_fifo` entity has port `wr_usedw`. Let me verify that's actually used... The `vga_subsystem.vhd` declares the asyn_fifo component at line 95 with `wr_usedw` and connects it at line 261. The `camera_subsystem/asyn_fifo.vhd` does NOT have `wr_usedw`, but `camera_subsystem.vhd` doesn't need it. There are two separate `asyn_fifo.vhd` files in two different subsystem directories. The VGA one should be the one instantiated in VGA. Each subsystem project has its own local copy. This is fine.

### BUG H — `read_start_armed` can fire before SDRAM fills the FIFO (partial frame offset)
**File:** `vga_subsystem.vhd` lines 196–233

After vsync falling edge:
1. `read_start_armed <= '0'`, `read_start_ready <= '0'`
2. SDRAM starts filling VGA FIFO via reads
3. As soon as `fifo_empty = '0'` → `read_start_ready <= '1'`
4. During blanking with `vga_vsync='1'` and `vga_active='0'` → `read_start_armed <= '1'`
5. VGA interface starts reading

The problem: `vga_active` goes low during the blanking intervals at the bottom of frame (lines 480–524). The FIFO may get armed and start reading DURING the blanking of the CURRENT frame, before vsync even fires. Then vsync fires, disarms, SDRAM refills, and re-arms. This could cause the first displayed pixel to be at a non-zero offset.

**More importantly:** `fifo_rst_n = rst_n and vga_vsync`. The FIFO is held in reset during the 2-line vsync pulse. After vsync returns high, the FIFO is released. The SDRAM then fills it. The first vsync rising edge after reset release is when the FIFO can start filling. `read_start_armed` is gated on `vga_vsync='1' and vga_active='0'`, so it arms during the back-porch (after vsync goes high, before `h_count` returns to 0). This is the correct window. ✓

### Summary of real bugs to fix:

| ID | Severity | Location | Description |
|----|----------|----------|-------------|
| B  | High     | `vga_subsystem.vhd:183` | FIFO reset tied to vsync level — both wr and rd sides reset simultaneously, Altera dcfifo may not recover correctly when wr_rst_n is deasserted before rd_rst_n |
| C  | Critical | `stream_top.vhd:488` | SW(3)=bypass: all current testing is in bypass=1 mode. The SDRAM path has never been seen working because the test harness used bypass mode. The user needs SW(3)=0 for normal operation |
| D  | High | `sdram_interface.vhd:362` | Read-issue condition: `vga_vsync_sync = '1'` gating means reads only happen during ACTIVE SCAN. But VGA FIFO drain rate at 25MHz is much faster than SDRAM fill rate at 100MHz (read bandwidth). Reads during active scan only gives ≈640/800 = 80% duty cycle, which is enough but is tight |
| E  | High | `sdram_interface.vhd:362` | `rd_ptr < FRAME_PIXELS` check: after rd_ptr reaches 76800, the condition fails and reads stop. But rd_ptr is reset to 0 on vsync. If the SDRAM can't fill the VGA FIFO for an entire frame (76800 pixels × 16 bits = 1.2 Mbit) in one VGA frame period (16.7ms), the display will underflow. At 100MHz with burst-8, burst takes ~10ns per word → 76800 × 10ns = 0.768ms. VGA frame = 16.7ms. So SDRAM can fill the FIFO ~22× per frame. ✓ Bandwidth is fine |
| F  | High | `sdram_interface.vhd:345` | `wr_ptr` overflow: when `wr_ptr >= FRAME_PIXELS - 8`, it resets to 0. But this means the last 7 pixels of a frame (indices 76793–76799) are never written to SDRAM. Not catastrophic but causes 7-pixel corruption at the bottom of each frame |

---

## Root Cause Summary

**The user was running all tests in bypass mode (SW(3)=1).** Bypass is structurally broken (same rate camera and VGA, no reservoir). The SDRAM path is the intended path but has the following real issues to fix:

1. **VGA FIFO reset sequence** — The `dcfifo aclr` fires on `vga_vsync` going low. This is correct in principle, but both `wr_rst_n` and `rd_rst_n` go low together. After reset, the FIFO is empty. The SDRAM needs to fill it before `read_start_armed` fires. This sequence appears to work as designed, but there's a subtle issue: if the SDRAM starts reading `rd_ptr=0` on the NEXT frame's vsync, but the current frame's SDRAM write hasn't finished (only partial frame written), the read bank may contain a stale partial frame.

2. **Write-bank vs read-bank coordination** — `write_bank` flips on every `frame_done`. `read_bank <= not write_bank` flips on vsync when `new_frame_ready=1`. If the camera is at 30fps and VGA at 60fps, the camera produces 1 frame per 2 VGA frames. The display should show each camera frame for 2 VGA frames (freeze briefly), then update. This requires `new_frame_ready` to stay set across one full VGA frame if no new camera frame arrives. Currently it does — `new_frame_ready` is only cleared when `vga_vsync` falls AND it is '1'.

3. **Frame geometry mismatch** — Camera is 320×240, VGA is 640×480. Each camera pixel is displayed in a 2×2 block. `vga_interface` reads 320 pixels per even scan line and repeats them on odd scan lines via `line_buf`. The read rate is 320 reads per even line × 240 even lines = 76800 reads per VGA frame = exactly FRAME_PIXELS. ✓

4. **The actual persistent issue the user sees** — "display freezes when switching to SW(3)=0." This suggests that in non-bypass mode, the first `read_frame_valid` never fires (because the camera hasn't completed its first full frame into SDRAM before the first vsync comes), or `rd_ptr` is always reset before reaching `FRAME_PIXELS`, so the VGA FIFO starves repeatedly.

---

## Proposed Fixes

### Fix 1: Proper VGA FIFO reset (vga_subsystem.vhd)

Separate the write-side reset from the read-side reset. The write side should be reset on global `rst_n` only (not on vsync), so SDRAM can keep writing across vsync boundaries. The read side should be reset on vsync to flush stale data.

```vhdl
-- BEFORE:
fifo_rst_n <= rst_n and vga_vsync;
-- (applied to both wr_rst_n and rd_rst_n)

-- AFTER: apply separately in port map
wr_rst_n => rst_n,          -- write side never reset by vsync
rd_rst_n => rst_n and vga_vsync,  -- read side flushed on vsync
```

### Fix 2: Eliminate the `vga_vsync_sync` read-gate in sdram_interface (sdram_interface.vhd)

The condition `vga_vsync_sync = '1'` in the read-issue logic prevents reads during the vsync pulse (2 lines = 96µs). This is fine. But it also means the FIFO can only be fed during active scan + back/front porch. Let it also feed during blanking (except during vsync pulse itself) — and let it opportunistically fill the VGA FIFO during blanking so it's pre-loaded for the next frame.

Actually the better fix: remove the `vga_vsync_sync = '1'` gate and instead let `vga_fifo_full` naturally throttle. The FIFO is 4096 deep; the SDRAM can fill it quickly and stop when full. Don't artificially restrict to active scan.

```vhdl
-- BEFORE:
elsif read_frame_valid = '1' and vga_vsync_sync = '1' and
      vga_fifo_full = '0' and rd_ptr < FRAME_PIXELS then

-- AFTER:
elsif read_frame_valid = '1' and
      vga_fifo_full = '0' and rd_ptr < FRAME_PIXELS then
```

This allows the SDRAM to pre-fill the VGA FIFO during blanking, removing the race condition at frame start.

### Fix 3: Re-enable the FIFO almost-full threshold (vga_subsystem.vhd)

The commented-out almost-full threshold was disabled (lines 191–194). This means the back-pressure only activates when the FIFO is completely full (4096 entries). This leads to burst-then-starve behavior. Re-enable the threshold at ~3072 to keep the FIFO at a stable level.

```vhdl
-- BEFORE:
fifo_full <= fifo_wr_full;

-- AFTER:
fifo_almost_full <= '1' when (unsigned(fifo_wr_usedw) >= to_unsigned(FIFO_ALMOST_FULL_THRESH, fifo_wr_usedw'length))
                     else fifo_wr_full;
fifo_full <= fifo_almost_full;
```

### Fix 4: Improve `read_start_armed` logic (vga_subsystem.vhd)

Require at least 320 pixels (one camera scanline) in the VGA FIFO before starting reads. This ensures the first line is complete before display begins, preventing partial-line display at frame top.

```vhdl
-- BEFORE:
if fifo_empty = '0' then
    read_start_ready <= '1';
end if;

-- AFTER: require at least one full line (320 pixels)
if unsigned(fifo_usedw) >= to_unsigned(320, 12) then
    read_start_ready <= '1';
end if;
```

### Fix 5: Camera interface — remove 64-cycle frame_done hold, use 2-cycle pulse

The 64-cycle frame_done hold in `camera_interface.vhd` (lines 323, 348-354) means the SDRAM FSM's edge detector fires correctly, but is confusing. Reduce to 2 cycles which is the minimum for a reliable 2-FF synchroniser with the frequency ratio of PCLK:100MHz (~4:1, so 2 cycles of PCLK ≈ 8 cycles of 100MHz — more than enough for 2-FF capture).

Actually this is safe as-is. Not changing this.

### Fix 6: Write pointer wrap — fix off-by-7 at end of frame (sdram_interface.vhd)

```vhdl
-- BEFORE:
if wr_ptr >= FRAME_PIXELS - 8 then
    wr_ptr <= (others => '0');
else
    wr_ptr <= wr_ptr + 8;
end if;

-- AFTER: don't wrap mid-frame; let frame_done reset it
if wr_ptr + 8 < FRAME_PIXELS then
    wr_ptr <= wr_ptr + 8;
-- else: don't advance; frame_done will reset to 0
end if;
```

This prevents the pointer from wrapping back and overwriting the frame start before `frame_done` fires.

---

## Files to Modify

---

### sdram_interface.vhd

#### [MODIFY] [sdram_interface.vhd](file:///c:/Jensen/projects/fpga/live_stream/sdram_subsystem/sdram_interface.vhd)

- Remove `vga_vsync_sync = '1'` from the read-issue condition (Fix 2)
- Fix `wr_ptr` overflow guard (Fix 6)

---

### vga_subsystem.vhd

#### [MODIFY] [vga_subsystem.vhd](file:///c:/Jensen/projects/fpga/live_stream/vga_subsystem/vga_subsystem.vhd)

- Separate VGA FIFO write-side and read-side resets (Fix 1)
- Re-enable `fifo_almost_full` threshold back-pressure (Fix 3)
- Improve `read_start_armed` — require 320 pixels before starting (Fix 4)
- Update `asyn_fifo` port map to use separate `wr_rst_n` and `rd_rst_n`

---

### vga_subsystem/asyn_fifo.vhd

#### [MODIFY] [asyn_fifo.vhd](file:///c:/Jensen/projects/fpga/live_stream/vga_subsystem/asyn_fifo.vhd)

- Add separate `wr_rst_n` and `rd_rst_n` ports (currently unified).
- Update Altera `dcfifo` instantiation to use `aclr` based on both `wr_rst_n` and `rd_rst_n`.

---

## Verification Plan

### After programming:
1. Set SW(3)=0 (non-bypass), SW(1)=0, SW(9:8)=00, SW(6)=0, SW(7)=0
2. Run `sample_loop 10 200`
3. Expected in SCH: `rfv=1`, `st` cycling through 0–5, `rdptr` advancing  
4. Expected in VGST: `vusedw > 0` consistently
5. Expected UFLO: near zero or zero
6. Visual: clear 320×240 image displayed in 640×480 (2× upscaled) on monitor

> [!IMPORTANT]
> All previous debug samples were taken with **SW(3)=1 (bypass mode)**. After applying fixes, use **SW(3)=0** for all testing. Bypass mode is not a viable streaming path.

> [!WARNING]
> A full rebuild and re-flash is required after any `.vhd` change. These are RTL changes.

## Open Questions

1. The `vga_subsystem/asyn_fifo.vhd` differs from `camera_subsystem/asyn_fifo.vhd` — the VGA one has a `wr_usedw` output port but the camera one does not. Is this intentional? (Yes — each subsystem uses its own local copy, which is correct.)

2. Do you want to keep the bypass mode (SW(3)=1) as a functional path? If so, the bypass process needs a FIFO between camera and VGA, not direct passthrough. For now, the plan leaves bypass mode broken (as it was) and focuses on making the SDRAM path work.
