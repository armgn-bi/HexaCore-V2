open_project C:/Users/DELL/Desktop/Yazilim/HexaCore-V2/PROJE/vivado/hexacore_axu4evb/hexacore_axu4evb.xpr
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set_property PROGRAM.FILE {C:/Users/DELL/Desktop/Yazilim/HexaCore-V2/PROJE/vivado/hexacore_axu4evb/hexacore_axu4evb.runs/impl_1/axu4evb_top.bit} [get_hw_devices xczu4_1]
program_hw_devices [get_hw_devices xczu4_1]
close_hw_manager
close_project
