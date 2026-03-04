import sys
import os
print(f"Executable: {sys.executable}")
print(f"Prefix: {sys.prefix}")
print(f"Base Prefix: {sys.base_prefix}")
dll_name = f"python{sys.version_info.major}{sys.version_info.minor}.dll"
dll_path = os.path.join(os.path.dirname(sys.executable), dll_name)
print(f"DLL Expected: {dll_path}")
print(f"Exists: {os.path.exists(dll_path)}")
