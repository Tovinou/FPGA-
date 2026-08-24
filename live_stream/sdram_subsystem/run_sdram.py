"""
run_sdram.py — VUnit runner for SDRAM testbenches
===================================================

One TB per module:
    tb_sdram_controller.vhd  — low-level SDRAM command FSM
    tb_sdram_interface.vhd   — frame-buffer arbitrator
    tb_sdram_subsystem.vhd   — integration (controller + interface + 2-FF sync)

Usage:
    python run_sdram.py                          # all tests
    python run_sdram.py -v                       # verbose
    python run_sdram.py *tb_sdram_controller*    # controller only
    python run_sdram.py *tb_sdram_interface*     # interface only
    python run_sdram.py *tb_sdram_subsystem*     # subsystem only
    python run_sdram.py *tc_init*                # all init tests
    python run_sdram.py --gui *tc_write_read*    # open waveform

Requirements:
    pip install vunit-hdl
    apt install ghdl

File layout (all in same folder):
    sdram_controller.vhd    (corrected)
    sdram_interface.vhd     (corrected)
    sdram_subsystem.vhd
    tb_sdram_controller.vhd
    tb_sdram_interface.vhd
    tb_sdram_subsystem.vhd
    run_sdram.py

Note on simulation time:
    tc_init_* tests need ~200us simulation = ~20000 cycles @ 100MHz.
    This takes a few seconds per test in GHDL. Completely normal.
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

# ── Design files ───────────────────────────────────────────────────────────
lib.add_source_files("sdram_controller.vhd")
lib.add_source_files("sdram_interface.vhd")
lib.add_source_files("sdram_subsystem.vhd")

# ── Testbench files ────────────────────────────────────────────────────────
lib.add_source_files("tb/tb_sdram_controller.vhd")
lib.add_source_files("tb/tb_sdram_interface.vhd")
lib.add_source_files("tb/tb_sdram_subsystem.vhd")

# ── Per-test simulation time limits ───────────────────────────────────────
# A 5 ms stop-time safely covers init (>=200 us) and all current tests.
for tb_name in ("tb_sdram_controller", "tb_sdram_interface", "tb_sdram_subsystem"):
    lib.test_bench(tb_name).set_sim_option("ghdl.sim_flags", ["--stop-time=5ms"])

vu.main()
