# [OPEN] OV7670 Bus Order Debug

## Session
- Session ID: `ov7670-bus-order`
- Date: `2026-06-21`
- Scope: determine why `SW(9 downto 8)` remap modes do not improve the OV7670 image even though frame geometry is valid

## Symptoms
- User reports the image is "still bad as it was" after programming the build with the new data remap selector.
- Prior evidence already showed correct frame geometry with unstable pixel values.

## Current Evidence
- `camera_interface.vhd` now supports four `data_map_sel` modes.
- `camera_subsystem.vhd` and `stream_top.vhd` propagate `data_map_sel`.
- Clean build completed and FPGA was programmed successfully.
- Latest qualitative result: no visible improvement from the remap-selector experiment.
- User confirmed all four `SW(9..8)` modes look effectively the same with `SW(6)=0` and `SW(7)=0`.
- Fresh `STAT`/`GEOM` captures for `00`, `01`, `10`, and `11` all show stable geometry: `lines=240`, `pix_div256=300`, `frame_valid=1`.
- `STAT` remains effectively unchanged across all remap modes: `bypass=0 pclk=1 href=1 wr_rate=3 wr_recent=1 empty=1 has=0 usedw=0`, with only expected sampling variation on instantaneous `vs`.

## Falsifiable Hypotheses
1. The OV7670 `D[7:0]` lines are physically miswired or electrically marginal in a way that is not representable by the four current remap modes.
2. Pixel values are being sampled on the wrong effective PCLK edge even though line/frame geometry remains correct.
3. The camera outputs valid bars/image data, but byte values are corrupted before or during the first byte-pair latch in `camera_interface`.
4. The user tested multiple remap modes, but we do not yet have per-mode observations, so an actually better mode may have been missed.
5. The remaining fault is external hardware integrity rather than VHDL ordering logic.

## Hypothesis Status
- Hypothesis 4 is now weakened: the user reports all four remap modes behave the same.
- Hypothesis 4 is effectively rejected by the STP data and user observation.
- Hypothesis 1 is strengthened: simple logical remaps do not affect the visual failure or probe behavior.
- Hypotheses 2, 3, and 5 remain open.

## Interim Conclusion
- The camera timing/geometry path is still healthy.
- The current failure is below the level of frame geometry and above the level of image interpretation.
- The next useful evidence is direct observation of raw captured byte values and assembled RGB565 words inside `camera_interface`.

## PIX Probe Findings
- The `PIX` probe is active and confirmed in STP alongside `STAT` and `GEOM`.
- Across multiple remap modes, non-zero `raw` bytes do appear, so the camera data bus is not stuck at zero.
- The remap logic is behaving correctly:
  - mode `10`: `raw=A8 -> mapped=54`, `raw=94 -> mapped=49`
  - mode `11`: `raw=35 -> mapped=D4`, `raw=16 -> mapped=58`
- This strongly weakens the idea that the remaining issue is a simple logical bit-order bug inside the FPGA.
- The many `PIX=00000000` samples are likely from reading a live byte-level probe during blanking or between valid write events, not proof of a dead stream.
- Refined sticky-byte-pair logs still show valid non-zero byte pairs and correct logical transforms:
  - mode `00`: `raw0=3E raw1=16 pixel=3E16`, `raw0=35 raw1=A8 pixel=35A8`
  - mode `01`: `raw0=35 raw1=A8 pixel=538A`, `raw0=B1 raw1=94 pixel=1B49`
  - mode `10`: `raw0=A9 raw1=25 pixel=561A`, `raw0=3D raw1=92 pixel=3E61`
  - mode `11`: `raw0=A9 raw1=25 pixel=A694`, `raw0=3E raw1=16 pixel=F858`
- This confirms the FPGA is seeing changing camera bytes and applying the selected remap correctly.

## Instrumentation Revision
- Refined the `PIX` probe to hold the last valid raw byte pair and last packed RGB565 word instead of live single-byte values.
- Next STP capture should therefore report stable `raw0`, `raw1`, and `pixel` values from real successful pixel writes.
- Current follow-up instrumentation now latches the first successful pixel pair of each frame, which should make STP samples deterministic across reads if the upstream data is stable.

## Edge Test Result
- Falling-edge capture build produced the same bad image as the rising-edge build.
- The first-pixel probe remained perfectly stable across repeated reads on the falling-edge build as well.
- This weakens the "wrong PCLK edge" hypothesis as the primary root cause.

## Current Direction
- User chose to verify physical OV7670 `D[7:0]` wiring against the QSF first.
- After that audit, the next planned instrumentation step is to probe the first 8 pixels of the frame to infer any remaining deterministic byte/bit permutation.

## Next Evidence Needed
- Per-mode results for `SW(9..8)=00/01/10/11` with `SW(6)=0`, `SW(7)=0`.
- One fresh `STAT` + `GEOM` capture after programming this bitstream.
- Confirmation whether any mode changes color only, noise only, rolling only, or image structure.
