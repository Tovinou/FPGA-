[OPEN] OV7670 unstable stream

## Symptoms
- Live video remains noisy / rolling / unclear instead of stable streaming.
- `LED7` keeps blinking, so frame ends are being detected.
- `LED5` is partially on, indicating intermittent camera FIFO occupancy.
- `SW(5..4)=01` shows an image, but it is still noisy with lines.

## Latest Reproduction
1. Program the latest `.sof`.
2. Set `SW(3)=0`, `SW(1)=0`, `SW(5..4)=01`.
3. Observe unstable/noisy live video.

## Falsifiable Hypotheses
1. The camera capture logic is assembling the wrong number of pixels per frame, so the image geometry is corrupted before SDRAM.
2. The line count per frame is unstable, which would indicate HREF/VSYNC interpretation is still wrong even though frames are being detected.
3. Frames are being marked complete even when the captured pixel count is too low, causing invalid frame banks to be displayed.
4. The write path is active, but frame-to-frame pixel counts vary wildly, indicating byte alignment instability on the camera bus.
5. SDRAM/VGA are mostly functioning, and the dominant fault is upstream in capture quality rather than downstream buffering.

## Planned Evidence
- Expose per-frame captured line count and pixel count over ISSP/STAT.
- Expose a frame-valid indicator based on minimum expected geometry.
- Compare multiple sampled frames to see whether geometry is stable.

## Evidence Collected
- `INSTANCES={0 1 32 STAT} {1 1 32 GEOM}`
- 20 consecutive `GEOM` samples reported:
  - `lines=240`
  - `pix_div256=300`
  - `frame_valid=1`
- `STAT` varied slightly between samples, but frame geometry remained perfectly stable.
- Visual mode comparison:
  - `SW(3)=1` (bypass) shows only lines on screen
  - switching back to `SW(3)=0` causes the display to freeze
- Later direct `STAT` samples:
  - `SW(3)=0` -> `STAT=0077C27F`
  - `SW(3)=1` -> `STAT=007FC19F`
- OV7670 internal color-bar test pattern was enabled, but the display still does not stream cleanly.

## Hypothesis Status
1. The camera capture logic is assembling the wrong number of pixels per frame.
   - Rejected. Captured geometry is consistently 240 lines and 76800 pixels (`300 * 256`).
2. The line count per frame is unstable due to HREF/VSYNC interpretation.
   - Rejected. Line count is stable at 240 across all sampled frames.
3. Frames are being marked complete even when the captured pixel count is too low.
   - Rejected. `frame_valid=1` for all sampled frames and pixel count is stable.
4. Frame-to-frame pixel counts vary wildly due to byte alignment instability.
   - Rejected for gross geometry. Fine pixel corruption may still exist, but frame size is stable.
5. SDRAM/VGA are mostly functioning, and the dominant fault is upstream in capture quality rather than downstream buffering.
   - Confirmed stronger than before. Because bypass mode is also visually corrupted, SDRAM is not the primary source of the bad image.

## Current Best Explanation
- Frame geometry is correct, but pixel values are corrupted before or during direct VGA feed.
- Hot-switching `SW(3)` is not a reliable runtime action; freezing after switching back to SDRAM mode may be caused by mode changes without a clean reset.
- Because bypass mode is also corrupted and the camera's own digital color-bar pattern is not clean, the dominant fault is now most likely the physical/source-synchronous camera interface (PCLK/data timing or wiring integrity), not SDRAM or frame-size logic.

## Notes
- During this debug session, avoid further behavioral fixes until the new instrumentation is read from hardware.
