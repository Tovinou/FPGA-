from vunit import VUnit
import os
import sys

if "VUNIT_SIMULATOR" not in os.environ:
    if os.environ.get("SALT_LICENSE_SERVER") or os.environ.get("LM_LICENSE_FILE"):
        os.environ["VUNIT_SIMULATOR"] = "modelsim"
    else:
        os.environ["VUNIT_SIMULATOR"] = "ghdl"

vu = VUnit.from_argv(vhdl_standard="2008", compile_builtins=False)
vu.add_vhdl_builtins()
lib = vu.add_library("lib")
lib.add_source_files("debounce_explicit.vhd")
lib.add_source_files("tb/tb_debounce_explicit/tb_debounce_explicit.vhd")
vu.main()
