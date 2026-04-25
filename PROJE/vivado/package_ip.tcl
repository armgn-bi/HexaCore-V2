# ─────────────────────────────────────────────────────
# package_ip.tcl — HexaCore-V2 IP Paketleme Script'i
# Vivado IP Catalog'a SoC'ü IP olarak ekler
# ─────────────────────────────────────────────────────

set ip_name "hexacore_v2_soc"
set ip_vendor "hexacore"
set ip_library "user"
set ip_version "1.0"
set ip_display_name "HexaCore-V2 RISC-V SoC"
set ip_description "RV32I 5-stage pipeline RISC-V SoC with AXI4-Lite bus, UART, SPI, I2C, DSP FIR, and DQN accelerator"

# ══════════════════════════════════════════════════════
# IP Paketleme
# ══════════════════════════════════════════════════════
package_ip \
  -name $ip_name \
  -vendor $ip_vendor \
  -library $ip_library \
  -version $ip_version \
  -force \
  -dir ./ip_pack

# ══════════════════════════════════════════════════════
# IP Özellikleri
# ══════════════════════════════════════════════════════
set_property display_name $ip_display_name [ipx::current_core]
set_property description $ip_description [ipx::current_core]
set_property taxonomy {{/Embedded_Processing/Processors}} [ipx::current_core]

# ══════════════════════════════════════════════════════
# RTL Dosyalarını Ekle
# ══════════════════════════════════════════════════════
set rtl_dir [file normalize "../rtl"]

# SystemVerilog dosyaları
set sv_files [list \
  "$rtl_dir/riscv_pkg.sv" \
  "$rtl_dir/bus/axi_pkg.sv" \
  "$rtl_dir/alu.sv" \
  "$rtl_dir/alu_control.sv" \
  "$rtl_dir/main_control.sv" \
  "$rtl_dir/register_file.sv" \
  "$rtl_dir/imm_gen.sv" \
  "$rtl_dir/imem.sv" \
  "$rtl_dir/dmem.sv" \
  "$rtl_dir/branch_compare.sv" \
  "$rtl_dir/forwarding_unit.sv" \
  "$rtl_dir/hazard_unit.sv" \
  "$rtl_dir/riscv_pipeline.sv" \
  "$rtl_dir/bus/axi_master_if.sv" \
  "$rtl_dir/bus/axi_lite_slave.sv" \
  "$rtl_dir/bus/axi_dmem_slave.sv" \
  "$rtl_dir/bus/axi_interconnect.sv" \
  "$rtl_dir/dsp/dsp_filter_wrapper.sv" \
  "$rtl_dir/dqn/dqn_core.sv" \
  "$rtl_dir/dqn/dqn_accelerator.sv" \
  "$rtl_dir/uart/uart_fifo.sv" \
  "$rtl_dir/uart/uart_tx.sv" \
  "$rtl_dir/uart/uart_rx.sv" \
  "$rtl_dir/uart/axi_uart.sv" \
  "$rtl_dir/spi/spi_master.sv" \
  "$rtl_dir/spi/axi_spi.sv" \
  "$rtl_dir/i2c/i2c_master.sv" \
  "$rtl_dir/i2c/axi_i2c.sv" \
  "$rtl_dir/top/soc_top.sv" \
]

foreach f $sv_files {
  if {[file exists $f]} {
    set file_obj [ipx::add_files $f -exclude_from_gui]
    set_property type SystemVerilog [get_files -of_objects $file_obj]
  }
}

# Verilog dosyaları (DSP FIR)
set v_files [list \
  "$rtl_dir/dsp/FilterCoef.v" \
  "$rtl_dir/dsp/FilterTapSystolicWvldInC0.v" \
  "$rtl_dir/dsp/FilterTapSystolicPreAddWvlIn.v" \
  "$rtl_dir/dsp/subFilter.v" \
  "$rtl_dir/dsp/Filter.v" \
  "$rtl_dir/dsp/dsphdl_FIRFilter.v" \
]

foreach f $v_files {
  if {[file exists $f]} {
    set file_obj [ipx::add_files $f -exclude_from_gui]
    set_property type Verilog [get_files -of_objects $file_obj]
  }
}

# ══════════════════════════════════════════════════════
# Top Modülü Belirle
# ══════════════════════════════════════════════════════
set_property top soc_top [ipx::current_core]

# ══════════════════════════════════════════════════════
# Parametreleri Tanımla
# ══════════════════════════════════════════════════════
ipx::add_parameter IMEM_INIT_FILE {string} [ipx::current_core]
set_property value "imem.mem" [ipx::get_parameter IMEM_INIT_FILE [ipx::current_core]]
set_property display_name "IMEM Init File" [ipx::get_parameter IMEM_INIT_FILE [ipx::current_core]]

ipx::add_parameter DMEM_INIT_FILE {string} [ipx::current_core]
set_property value "dmem.mem" [ipx::get_parameter DMEM_INIT_FILE [ipx::current_core]]
set_property display_name "DMEM Init File" [ipx::get_parameter DMEM_INIT_FILE [ipx::current_core]]

# ══════════════════════════════════════════════════════
# Bellek Dosyalarını Ekle
# ══════════════════════════════════════════════════════
set mem_dir [file normalize "../tb"]
if {[file exists "$mem_dir/imem_base.mem"]} {
  set file_obj [ipx::add_files "$mem_dir/imem_base.mem" -exclude_from_gui]
  set_property type {Any} [get_files -of_objects $file_obj]
  set_property is_include false [get_files -of_objects $file_obj]
}
if {[file exists "$mem_dir/dmem.mem"]} {
  set file_obj [ipx::add_files "$mem_dir/dmem.mem" -exclude_from_gui]
  set_property type {Any} [get_files -of_objects $file_obj]
  set_property is_include false [get_files -of_objects $file_obj]
}

# ══════════════════════════════════════════════════════
# IP'yi Kaydet
# ══════════════════════════════════════════════════════
ipx::create_core_gui_information [ipx::current_core]
ipx::save_core [ipx::current_core]

puts "════════════════════════════════════════════════════"
puts " HexaCore-V2 SoC IP paketlendi!"
puts " IP: $ip_name v$ip_version"
puts " Konum: ./ip_pack/$ip_name-$ip_version.zip"
puts ""
puts " IP'yi Vivado IP Catalog'a eklemek için:"
puts "   1. Vivado GUI'de: Tools -> Settings -> IP -> Repository"
puts "   2. ./ip_pack dizinini ekle"
puts "   3. IP Catalog'da $ip_display_name arat"
puts "════════════════════════════════════════════════════"
