"""
run.py — VUnit runner for camera subsystem testbenches
=======================================================

One TB per module:
    tb_i2c_top.vhd           — SCCB master / OV7670 register writer
    tb_camera_interface.vhd  — pixel capture FSM
    tb_camera_subsystem.vhd  — full integration (i2c + capture + CDC FIFO)

Usage:
    python run.py                              # all tests
    python run.py -v                           # verbose
    python run.py *tb_i2c_top*                 # SCCB tests only
    python run.py *tb_camera_interface*        # capture FSM tests only
    python run.py *tb_camera_subsystem*        # integration tests only
    python run.py *tc_pixel_assembly*          # single test by name
    python run.py --gui *tc_cdc_pixel*         # waveform viewer

Requirements:
    pip install vunit-hdl
    apt install ghdl   (or download from https://github.com/ghdl/ghdl/releases)

File layout (all in same folder):
    asyn_fifo.vhd             (corrected version — no nested rising_edge)
    i2c_top.vhd               (corrected — HALF_PERIOD=120, soft-reset delay)
    camera_interface.vhd      (corrected — i2c_done port, S_WAIT_CONFIG state)
    camera_subsystem.vhd      (corrected — i2c_done wired to camera_interface)
    tb_i2c_top.vhd
    tb_camera_interface.vhd
    tb_camera_subsystem.vhd
    run.py
"""

import os

os.environ.setdefault("VUNIT_SIMULATOR", "ghdl")

from vunit import VUnit
from vunit.sim_if.ghdl import GHDLInterface


_orig_determine_backend = GHDLInterface.determine_backend


def _determine_backend_compat(prefix):
    try:
        return _orig_determine_backend(prefix)
    except AssertionError:
        output = GHDLInterface._get_version_output(prefix)
        if "mcode JIT code generator" in output:
            return "mcode"
        raise


GHDLInterface.determine_backend = classmethod(lambda cls, prefix: _determine_backend_compat(prefix))

vu = VUnit.from_argv(compile_builtins=False)
vu.add_vhdl_builtins()

lib = vu.add_library("lib")

# ── Design files (leaf first) ──────────────────────────────────────────────
lib.add_source_files("asyn_fifo.vhd")
lib.add_source_files("i2c_top.vhd")
lib.add_source_files("camera_interface.vhd")
lib.add_source_files("camera_subsystem.vhd")

# ── Testbench files ────────────────────────────────────────────────────────
lib.add_source_files("tb/tb_i2c_top.vhd")
lib.add_source_files("tb/tb_camera_interface.vhd")
lib.add_source_files("tb/tb_camera_subsystem.vhd")

# ── Per-test simulator options ─────────────────────────────────────────────
# Tests that wait for i2c_done need up to 45ms simulation time
# Increase GHDL stop time for slow tests
i2c_slow_tests = [
    ("tb_i2c_top",          "tc_done_asserts"),
    ("tb_i2c_top",          "tc_soft_reset_delay"),
    ("tb_camera_subsystem", "tc_fifo_fills_after_i2c"),
    ("tb_camera_subsystem", "tc_cdc_pixel_integrity"),
    ("tb_camera_subsystem", "tc_frame_done_sync"),
    ("tb_camera_subsystem", "tc_fifo_empty_between"),
]
for tb_name, tc_name in i2c_slow_tests:
    lib.test_bench(tb_name).test(tc_name).set_sim_option(
        "ghdl.sim_flags", ["--stop-time=100ms"]
    )

vu.main()
