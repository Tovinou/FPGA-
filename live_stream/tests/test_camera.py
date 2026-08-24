import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from shutil import which
from shutil import copyfile


class TestCamera(unittest.TestCase):
    def test_camera_vunit(self) -> None:
        if which("ghdl") is None:
            self.skipTest("GHDL not found in PATH")

        try:
            import vunit  # noqa: F401
        except Exception:
            self.skipTest("vunit-hdl not installed in current Python environment")

        repo_root = Path(__file__).resolve().parents[1]
        run_py = repo_root / "camera_subsystem" / "run.py"
        if not run_py.exists():
            self.fail(f"Missing VUnit runner: {run_py}")

        env = dict(os.environ)
        env["VUNIT_SIMULATOR"] = "ghdl"

        completed = subprocess.run(
            [sys.executable, str(run_py), "*tc_cdc_pixel_integrity*"],
            cwd=str(run_py.parent),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        if completed.returncode != 0:
            known_skip_markers = (
                "Unable to determine the GHDL backend",
                "license checkout failed",
                "No such feature exists",
                "Failed to find simulator",
            )
            if any(m in completed.stdout for m in known_skip_markers):
                self.skipTest(completed.stdout.strip())
            self.fail(completed.stdout)

    def test_capture_camera_frame_ppm(self) -> None:
        if which("ghdl") is None:
            self.skipTest("GHDL not found in PATH")

        repo_root = Path(__file__).resolve().parents[1]
        tb = repo_root / "camera_subsystem" / "tb" / "tb_camera_capture_ppm.vhd"
        if not tb.exists():
            self.fail(f"Missing testbench: {tb}")

        sources = [
            repo_root / "camera_subsystem" / "asyn_fifo.vhd",
            repo_root / "camera_subsystem" / "camera_interface.vhd",
            repo_root / "camera_subsystem" / "i2c_top.vhd",
            repo_root / "camera_subsystem" / "camera_subsystem.vhd",
            tb,
        ]

        for src in sources:
            if not src.exists():
                self.fail(f"Missing source: {src}")

        out_ppm = repo_root / "output_files" / "camera_capture.ppm"
        if out_ppm.exists():
            out_ppm.unlink()

        with tempfile.TemporaryDirectory(prefix="ghdl_cam_") as td:
            cwd = Path(td)
            tmp_ppm = cwd / "camera_capture.ppm"
            analyze = ["ghdl", "-a", "--std=08", *[str(p) for p in sources]]
            elab = ["ghdl", "-e", "--std=08", "tb_camera_capture_ppm"]
            run = ["ghdl", "-r", "--std=08", "tb_camera_capture_ppm", "--stop-time=80ms"]

            for cmd in (analyze, elab, run):
                completed = subprocess.run(
                    cmd,
                    cwd=str(cwd),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                )
                if completed.returncode != 0:
                    self.fail(completed.stdout)

            if not tmp_ppm.exists():
                self.fail(f"PPM not created by simulator: {tmp_ppm}")
            out_ppm.parent.mkdir(parents=True, exist_ok=True)
            copyfile(tmp_ppm, out_ppm)

        self.assertTrue(out_ppm.exists(), f"PPM not created: {out_ppm}")
        self.assertGreater(out_ppm.stat().st_size, 1024, "PPM output too small to be a frame")


if __name__ == "__main__":
    unittest.main()
