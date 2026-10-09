import os

os.environ.setdefault("VUNIT_SIMULATOR", "ghdl")

from vunit import VUnit
import os
import sys

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



vu = VUnit.from_argv(vhdl_standard="2008", compile_builtins=False)
vu.add_vhdl_builtins()
lib = vu.add_library("lib")
lib.add_source_files("debounce_explicit.vhd")
lib.add_source_files("tb/tb_debounce_explicit/tb_debounce_explicit.vhd")
vu.main()
