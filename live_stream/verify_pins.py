import os
import re

QSF_FILE = 'stream_top.qsf'
VHD_FILE = 'stream_top.vhd'

def parse_vhd_ports(vhd_path):
    ports = {}
    with open(vhd_path, 'r') as f:
        content = f.read()

    # Extract the port section of the entity stream_top
    # Find "port (" and then find "end entity" or "end stream_top"
    port_start = content.lower().find('port (')
    if port_start == -1:
        port_start = content.lower().find('port(')
        
    end_entity = content.lower().find('end entity', port_start)
    if end_entity == -1:
        end_entity = content.lower().find('end stream_top', port_start)

    if port_start == -1 or end_entity == -1:
        print("Could not find port declaration in VHD")
        return ports

    port_section = content[port_start:end_entity]
    
    # Simple regex to find port declarations
    lines = port_section.split('\n')
    for line in lines:
        line = line.split('--')[0].strip() # remove comments
        if not line:
            continue
        
        # Match port name and type
        # e.g. "VGA_R : out std_logic_vector(3 downto 0);"
        match = re.search(r'([A-Za-z0-9_]+)\s*:\s*(in|out|inout)\s+(std_logic_vector\s*\(\s*(\d+)\s+downto\s+(\d+)\s*\)|std_logic)', line, re.IGNORECASE)
        if match:
            name = match.group(1)
            is_vector = match.group(3).lower().startswith('std_logic') and 'downto' in match.group(3).lower()
            if is_vector:
                high = int(match.group(4))
                low = int(match.group(5))
                for i in range(low, high + 1):
                    ports[name + "[" + str(i) + "]"] = False
            else:
                ports[name] = False
    return ports

def check_qsf_pins(qsf_path, ports):
    if not os.path.exists(qsf_path):
        return
        
    assignments = {}
    with open(qsf_path, 'r') as f:
        for line in f:
            if line.startswith('set_location_assignment'):
                parts = line.split()
                if len(parts) >= 4 and parts[2] == '-to':
                    pin = parts[1]
                    port_name = parts[3]
                    assignments[port_name] = pin

    missing_pins = []
    for port in ports.keys():
        if port in assignments:
            ports[port] = True
        else:
            missing_pins.append(port)
            
    extra_pins = [port for port in assignments.keys() if port not in ports]

    print("\n--- Summary ---")
    if not missing_pins and not extra_pins:
        print("SUCCESS: All top-level VHDL ports have exactly one physical pin assignment in the QSF!")
    else:
        if missing_pins:
            print("WARNING: " + str(len(missing_pins)) + " ports in VHDL are missing physical pin assignments in QSF:")
            for p in missing_pins:
                print("  - " + p)
        if extra_pins:
            print("WARNING: " + str(len(extra_pins)) + " pin assignments in QSF do not correspond to any VHDL port:")
            for p in extra_pins:
                print("  - " + p + " (assigned to " + assignments[p] + ")")

if __name__ == "__main__":
    ports = parse_vhd_ports(VHD_FILE)
    check_qsf_pins(QSF_FILE, ports)
