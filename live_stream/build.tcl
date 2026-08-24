# Build script for live_stream FPGA project
# Compiles the project to generate bitstream

# Load required packages
load_package flow

# Open project
project_open live_stream.qpf

# Run full compilation: Analysis, Synthesis, Place & Route, Assembly
execute_flow -compile

# Close project
project_close

puts "Build complete!"

