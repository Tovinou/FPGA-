"""
run.py — VUnit test runner for VGA subsystem
Usage:
    python run.py                        # run all tests
    python run.py -v                     # verbose
    python run.py *tc_vga_core*          # run only vga_core tests
    python run.py *tc_vga_interface*     # run only interface tests
    python run.py *tc_vga_subsystem*     # run only subsystem tests
    python run.py --gui                  # open ModelSim/GHDL waveform

    # Run just one module during development
    python run.py *tb_vga_core*

    # Run all, stop on first failure
    python run.py --fail-fast

    # Open waveform for a specific test
    python run.py --gui *tc_rgb565_red*

Requires VUnit:  pip install vunit-hdl
Simulator:       GHDL (free)  or  ModelSim / Questa
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

# Create VUnit instance — auto-detects GHDL or ModelSim on PATH
vu = VUnit.from_argv()
vu.add_vhdl_builtins()

# Add source library
lib = vu.add_library("lib")

# Design files (leaf first, then wrappers, then TB)
lib.add_source_files("asyn_fifo.vhd")
lib.add_source_files("vga_core.vhd")
lib.add_source_files("vga_interface.vhd")
lib.add_source_files("vga_subsystem.vhd")
lib.add_source_files("tbvga/tb_asyn_fifo.vhd")
lib.add_source_files("tbvga/tb_vga_core.vhd")
lib.add_source_files("tbvga/tb_vga_interface.vhd")
lib.add_source_files("tbvga/tb_vga_subsystem.vhd")

# Optional: per-test simulator settings
tb_core = lib.test_bench("tb_vga_core")
tb_core.test("tc_active_count").set_sim_option("ghdl.sim_flags", ["--stop-time=70ms"])
tb_core.test("tc_frame_period").set_sim_option("ghdl.sim_flags", ["--stop-time=70ms"])

vu.main()
