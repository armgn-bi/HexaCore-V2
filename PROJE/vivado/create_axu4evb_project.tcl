# =========================================================
# Vivado Project Creation Script for ALINX AXU4EVB-P
# Target: Zynq UltraScale+ XCZU4EV-SFVC784-1-I
# =========================================================

set project_name "hexacore_axu4evb"
set project_dir "./$project_name"
set part "xczu4ev-sfvc784-1-i"

# Create project
create_project $project_name $project_dir -part $part -force

# Add RTL Source Files
add_files ../rtl/riscv_pkg.sv
add_files ../rtl/alu.sv
add_files ../rtl/alu_control.sv
add_files ../rtl/branch_compare.sv
add_files ../rtl/dmem.sv
add_files ../rtl/forwarding_unit.sv
add_files ../rtl/hazard_unit.sv
add_files ../rtl/imem.sv
add_files ../rtl/imm_gen.sv
add_files ../rtl/main_control.sv
add_files ../rtl/register_file.sv
add_files ../rtl/riscv_pipeline.sv

catch {add_files [glob -nocomplain ../rtl/bus/*.sv]}
catch {add_files [glob -nocomplain ../rtl/dqn/*.sv]}
catch {add_files [glob -nocomplain ../rtl/dsp/*.v]}
catch {add_files [glob -nocomplain ../rtl/dsp/*.sv]}
catch {add_files [glob -nocomplain ../rtl/hexacore/*.sv]}
catch {add_files [glob -nocomplain ../rtl/i2c/*.sv]}
catch {add_files [glob -nocomplain ../rtl/peripherals/*.sv]}
catch {add_files [glob -nocomplain ../rtl/spi/*.sv]}
catch {add_files [glob -nocomplain ../rtl/uart/*.sv]}

# Add Top Level
add_files ../rtl/top/soc_top.sv
add_files ../rtl/top/axu4evb_top.sv
set_property top axu4evb_top [current_fileset]

# Add Constraints
add_files -fileset constrs_1 ../constraints/axu4evb_p.xdc

# Run Synthesis
puts "Starting Synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Run Implementation and Generate Bitstream
puts "Starting Implementation..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "========================================================="
puts "AXU4EVB-P Project created and bitstream generated successfully!"
puts "You can now open Vivado Hardware Manager and program the board."
puts "========================================================="
