
import os
import sys
import shutil
import argparse
import subprocess

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
TOP_ENTITY = "ping_pong_game"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def run(cmd, cwd=None, env=None):
    print(f"Running: {' '.join(cmd)}")
    subprocess.check_call(cmd, cwd=cwd, env=env)

def find_ghdl():
    return shutil.which("ghdl") or "ghdl"

def find_vsim():
    return shutil.which("vsim") or "vsim"

def find_cocotb_fli():
    try:
        # Try using cocotb-config
        cmd = ["cocotb-config", "--lib-name-path", "fli", "questa"]
        if sys.platform == "win32":
            cmd[-1] = "modelsim" # usually maps to modelsim on windows? or questa?
        # Actually, let's just try "questa" first, then "modelsim"
        try:
            return subprocess.check_output(["cocotb-config", "--lib-name-path", "fli", "questa"], encoding="utf-8").strip()
        except:
            return subprocess.check_output(["cocotb-config", "--lib-name-path", "fli", "modelsim"], encoding="utf-8").strip()
    except:
        # Fallback to manual search
        import cocotb
        lib_dir = os.path.join(os.path.dirname(cocotb.__file__), "libs")
        potential_libs = [
            "libcocotbfli_modelsim.dll",
            "cocotbfli_modelsim.dll",
            "libcocotbfli_questa.dll", 
            "cocotbfli_questa.dll"
        ]
        for lib in potential_libs:
            path = os.path.join(lib_dir, lib)
            if os.path.exists(path):
                return path
        # If still not found, return empty string or raise
        print("WARNING: Could not find Cocotb FLI library automatically.")
        return ""

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run_verification(simulator="questa", gui=False):
    root_dir = os.path.dirname(os.path.abspath(__file__))
    sim_build = os.path.join(root_dir, "sim_build")
    
    # Environment Setup
    env = os.environ.copy()
    
    env["COCOTB_REDUCED_LOG_FMT"] = "1"
    env["MODULE"] = "test_ping_pong_top,test_peripherals"
    env["COCOTB_TEST_MODULES"] = "test_ping_pong_top,test_peripherals"
    env["TOPLEVEL"] = TOP_ENTITY
    env["TOPLEVEL_LANG"] = "vhdl"
    
    # PYTHONPATH must include the test directory
    pypath = env.get("PYTHONPATH", "")
    tests_dir = os.path.join(root_dir, "tests")
    if tests_dir not in pypath:
        env["PYTHONPATH"] = tests_dir + os.pathsep + pypath

    # Set PYGPI_PYTHON_BIN to the current python executable
    env["PYGPI_PYTHON_BIN"] = sys.executable.replace("\\", "/")

    # (Re)create sim_build
    if os.path.exists(sim_build):
        shutil.rmtree(sim_build)
    os.makedirs(sim_build)

    # ------------------------------------------------------------------
    # GHDL Flow
    # ------------------------------------------------------------------
    if simulator == "ghdl":
        ghdl_exe = find_ghdl()
        print(f"Using Simulator: {ghdl_exe}")
        
        # 1. Analyze (Import)
        print("\n=== Step 1: Analyzing VHDL (GHDL) ===")
        # Find all VHDL files
        vhdl_files = []
        for f in os.listdir(root_dir):
            if f.lower().endswith(".vhdl") or f.lower().endswith(".vhd"):
                # Ensure TOP_ENTITY is last (simplistic dependency handling)
                if TOP_ENTITY in f:
                    continue
                vhdl_files.append(os.path.join(root_dir, f))
        
        # Add Top Entity last
        top_file = os.path.join(root_dir, f"{TOP_ENTITY}.vhdl")
        if not os.path.exists(top_file):
             top_file = os.path.join(root_dir, f"{TOP_ENTITY}.vhd")
        vhdl_files.append(top_file)

        # Copy files to sim_build to avoid cluttering root
        # GHDL analyzes in current directory by default
        for f in vhdl_files:
            shutil.copy(f, sim_build)
            
        # Run analysis
        # ghdl -i --std=08 *.vhdl
        cmd_analyze = [ghdl_exe, "-i", "--std=08"] + [os.path.basename(f) for f in vhdl_files]
        run(cmd_analyze, cwd=sim_build, env=env)
        
        # 2. Elaborate (Make)
        print("\n=== Step 2: Elaborating (GHDL) ===")
        # ghdl -m --std=08 TOP_ENTITY
        cmd_make = [ghdl_exe, "-m", "--std=08", TOP_ENTITY]
        run(cmd_make, cwd=sim_build, env=env)
        
        # 3. Run
        print("\n=== Step 3: Running Simulation (GHDL) ===")
        # ghdl -r --std=08 TOP_ENTITY --vpi=cocotb_vpi_entry_point
        # Note: cocotb needs to know where the VPI library is.
        # For GHDL, we typically rely on cocotb-config to find the vpi lib, 
        # but modern GHDL might handle it differently.
        # Standard way: --vpi=path/to/libcocotbvpi_ghdl.so (or .dll on Windows)
        
        # We will let cocotb-config find the library path
        try:
            lib_path = subprocess.check_output(["cocotb-config", "--lib-name-path", "vpi", "ghdl"], encoding="utf-8").strip()
        except:
            # Fallback
            import cocotb
            lib_dir = os.path.join(os.path.dirname(cocotb.__file__), "libs")
            # Windows extension might be different, but GHDL on Windows often uses .dll
            lib_path = os.path.join(lib_dir, "cocotbvpi_ghdl.dll")
            
        cmd_run = [ghdl_exe, "-r", "--std=08", TOP_ENTITY, f"--vpi={lib_path}"]
        
        # Add waveform dumping if GUI requested (GHDL doesn't have a native GUI like Questa)
        # We can dump to VCD/FST and open GTKWave
        if gui:
            print("NOTE: GUI mode for GHDL implies dumping waveforms to wave.ghw")
            cmd_run.append("--wave=wave.ghw")
            
        run(cmd_run, cwd=sim_build, env=env)
        
        if gui:
            print("\nWaveform generated: sim_build/wave.ghw")
            print("You can open it with GTKWave.")

    # ------------------------------------------------------------------
    # Questa Flow
    # ------------------------------------------------------------------
    elif simulator == "questa":
        vsim_exe = find_vsim()
        vsim_dir = os.path.dirname(vsim_exe) if os.path.isabs(vsim_exe) else os.path.dirname(shutil.which("vsim"))
        
        print(f"Using Simulator: {vsim_exe}")
        
        cocotb_fli = find_cocotb_fli()
        print(f"Using Cocotb FLI: {cocotb_fli}")

        # Handle License (Questa specific)
        license_path = r"C:\altera_lite\license.dat"
        final_license_val = ""
        if os.path.isdir(license_path):
            lic_files = [os.path.join(license_path, f) for f in os.listdir(license_path) if f.endswith(".dat")]
            if lic_files:
                final_license_val = ";".join(lic_files)
        elif os.path.exists(license_path):
            final_license_val = license_path
            
        if final_license_val:
            env["LM_LICENSE_FILE"] = final_license_val
            env["MGLS_LICENSE_FILE"] = final_license_val
            env["SALT_LICENSE_SERVER"] = final_license_val
            print(f"Set License: {final_license_val}")
        
        # Set LIBPYTHON_LOC (Questa specific)
        python_dir = os.path.dirname(sys.executable)
        ver = sys.version_info
        dll_name = f"python{ver.major}{ver.minor}.dll"
        dll_path = os.path.join(python_dir, dll_name)
        if os.path.exists(dll_path):
            env["LIBPYTHON_LOC"] = dll_path
            print(f"Set LIBPYTHON_LOC: {dll_path}")
            env["PATH"] = python_dir + os.pathsep + env.get("PATH", "")
        else:
            print(f"WARNING: Could not find Python DLL at {dll_path}")

        # Step 1: Create Library
        print("\n=== Step 1: Creating Library ===")
        vlib_exe = os.path.join(vsim_dir, "vlib")
        run([vlib_exe, "work"], cwd=sim_build, env=env)

        # Step 2: Compile VHDL
        print("\n=== Step 2: Compiling VHDL ===")
        vcom_exe = os.path.join(vsim_dir, "vcom")
        
        vhdl_files = []
        for f in os.listdir(root_dir):
            if f.lower().endswith(".vhdl") or f.lower().endswith(".vhd"):
                if TOP_ENTITY in f:
                    continue
                vhdl_files.append(os.path.join(root_dir, f))
        
        # Compile dependencies
        if vhdl_files:
            run([vcom_exe, "-2008"] + vhdl_files, cwd=sim_build, env=env)
            
        # Compile Top Entity
        top_file = os.path.join(root_dir, f"{TOP_ENTITY}.vhdl")
        if not os.path.exists(top_file):
             top_file = os.path.join(root_dir, f"{TOP_ENTITY}.vhd")
        run([vcom_exe, "-2008", top_file], cwd=sim_build, env=env)

        # Step 3: Run Simulation
        print("\n=== Step 3: Running Simulation ===")
        vsim_cmd = [vsim_exe]
        if not gui:
            vsim_cmd.append("-c")
        
        # Optimization args
        vsim_cmd.extend([
            "-voptargs=+acc", 
            "-G", "freq=1000", 
            "-G", "slow_clk_nb_cycles=5"
        ])
        
        if gui:
            vsim_cmd.extend(["-do", "add wave -r /*; run -all"])
        else:
            vsim_cmd.extend(["-do", "run -all; quit"])

        # Foreign interface loading
        # The FLI string format is crucial: "function_name path_to_dll"
        vsim_cmd.extend([
            "-foreign", f"cocotb_init {cocotb_fli}", 
            f"work.{TOP_ENTITY}"
        ])

        run(vsim_cmd, cwd=sim_build, env=env)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run Cocotb verification")
    parser.add_argument("--gui", action="store_true", help="Run in GUI mode")
    parser.add_argument("--simulator", default="questa", choices=["questa", "ghdl"], help="Simulator to use")
    args = parser.parse_args()
    
    run_verification(simulator=args.simulator, gui=args.gui)
