# ─────────────────────────────────────────────────────
# create_project.tcl — HexaCore-V2 Vivado Proje Olusturma
# Hedef: Nexys A7-100T (xc7a100tcsg324-1)
#
# Kullanim:
#   cd PROJE/vivado
#   vivado -mode batch -source create_project.tcl
#
# veya Vivado GUI icinden:
#   source create_project.tcl
# ─────────────────────────────────────────────────────

# ══════════════════════════════════════════════════════
# Proje Dizini Belirleme
# ══════════════════════════════════════════════════════
set proj_name "hexacore_v2"
set proj_dir  [file normalize [file dirname [info script]]]
set rtl_dir   [file normalize "$proj_dir/../rtl"]
set tb_dir    [file normalize "$proj_dir/../tb"]
set sim_dir   [file normalize "$proj_dir/../sim"]
set constr_dir [file normalize "$proj_dir/../constraints"]

# ══════════════════════════════════════════════════════
# Projeyi Olustur
# ══════════════════════════════════════════════════════
create_project $proj_name "$proj_dir/$proj_name" -part xc7a100tcsg324-1 -force

# Board part ayarla (opsiyonel — board dosyalari yukluyse)
# set_property board_part digilentinc.com:nexys-a7-100t:part0:1.4 [current_project]

# Dil ve hedef ayarlari
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# ══════════════════════════════════════════════════════
# SystemVerilog Kaynak Dosyalari
# ══════════════════════════════════════════════════════

# Paket dosyalari (oncelik sirasina gore eklenir)
set sv_sources [list \
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
  "$rtl_dir/top/soc_top.sv" \
  "$rtl_dir/top/nexys_a7_top.sv" \
]

foreach f $sv_sources {
  if {[file exists $f]} {
    add_files -norecurse $f
    set_property file_type SystemVerilog [get_files [file tail $f]]
  } else {
    puts "UYARI: Dosya bulunamadi: $f"
  }
}

# ══════════════════════════════════════════════════════
# Verilog Kaynak Dosyalari (DSP FIR — MATLAB HDL Coder)
# ══════════════════════════════════════════════════════

set v_sources [list \
  "$rtl_dir/dsp/FilterCoef.v" \
  "$rtl_dir/dsp/FilterTapSystolicWvldInC0.v" \
  "$rtl_dir/dsp/FilterTapSystolicPreAddWvlIn.v" \
  "$rtl_dir/dsp/subFilter.v" \
  "$rtl_dir/dsp/Filter.v" \
  "$rtl_dir/dsp/dsphdl_FIRFilter.v" \
]

foreach f $v_sources {
  if {[file exists $f]} {
    add_files -norecurse $f
    set_property file_type Verilog [get_files [file tail $f]]
  } else {
    puts "UYARI: DSP Verilog dosyasi bulunamadi: $f"
  }
}

# ══════════════════════════════════════════════════════
# Constraint Dosyasi
# ══════════════════════════════════════════════════════
if {[file exists "$constr_dir/nexys_a7.xdc"]} {
  add_files -fileset constrs_1 -norecurse "$constr_dir/nexys_a7.xdc"
} else {
  puts "UYARI: XDC dosyasi bulunamadi: $constr_dir/nexys_a7.xdc"
}

# ══════════════════════════════════════════════════════
# Bellek Baslangic Dosyalari (.mem)
# ══════════════════════════════════════════════════════
# $readmemh calisma dizininden okur, sim ve calisma dizinlerine kopyala
set mem_files [list \
  "$tb_dir/imem_base.mem" \
  "$tb_dir/dmem.mem" \
]

foreach f $mem_files {
  if {[file exists $f]} {
    add_files -norecurse $f
    set_property used_in_synthesis true [get_files [file tail $f]]
    set_property used_in_simulation true [get_files [file tail $f]]
  }
}

# Varsayilan imem.mem olarak imem_base.mem'i kopyala
set work_dir "$proj_dir/$proj_name/$proj_name.runs"
if {[file exists "$tb_dir/imem_base.mem"]} {
  file copy -force "$tb_dir/imem_base.mem" "$proj_dir/$proj_name/imem.mem"
}
if {[file exists "$tb_dir/dmem.mem"]} {
  file copy -force "$tb_dir/dmem.mem" "$proj_dir/$proj_name/dmem.mem"
}

# ══════════════════════════════════════════════════════
# Top Modul Ayari
# ══════════════════════════════════════════════════════
set_property top nexys_a7_top [current_fileset]
update_compile_order -fileset sources_1

# ══════════════════════════════════════════════════════
# Sentez & Implementasyon Ayarlari
# ══════════════════════════════════════════════════════

# Sentez stratejisi: Vivado Synthesis Defaults
set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]

# Implementasyon stratejisi: Performance_ExplorePostRoutePhysOpt
# (zamanlama kapanmasi icin agresif optimizasyon)
set_property strategy "Performance_ExplorePostRoutePhysOpt" [get_runs impl_1]

# ══════════════════════════════════════════════════════
# Timing Optimization Ayarlari
# ══════════════════════════════════════════════════════

# Agresif timing optimizasyon parametreleri
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE ExploreWithRemap [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.RETIMING true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.SSLHIFT true [get_runs impl_1]

# Post-route physical optimization
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE ExploreWithRemap [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.RETIMING true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.SSLHIFT true [get_runs impl_1]

# Routing optimizasyon
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]

# Genel parametre gecisi (IMEM/DMEM init dosyalari)
# Not: $readmemh dosya yolu sentez sirasinda calisma dizinine gore cozulur.
# "imem.mem" ve "dmem.mem" dosyalari proje dizinine kopyalanmistir.

# ══════════════════════════════════════════════════════
# Simülasyon Ayarlari (Opsiyonel)
# ══════════════════════════════════════════════════════
# TB dosyalarini simülasyon fileset'ine ekle
set tb_files [glob -nocomplain "$tb_dir/*.sv" "$tb_dir/soc_tb/*.sv" "$tb_dir/periph_tb/*.sv"]
foreach f $tb_files {
  if {[file exists $f]} {
    add_files -fileset sim_1 -norecurse $f
    set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] [file tail $f]]
  }
}

# ══════════════════════════════════════════════════════
# Bilgi Mesaji
# ══════════════════════════════════════════════════════
puts "════════════════════════════════════════════════════"
puts " HexaCore-V2 Vivado projesi olusturuldu!"
puts " Proje: $proj_dir/$proj_name/$proj_name.xpr"
puts " Hedef: xc7a100tcsg324-1 (Nexys A7-100T)"
puts " Top:   nexys_a7_top"
puts ""
puts " Sonraki adimlar:"
puts "   1. Vivado GUI'de projeyi ac"
puts "   2. Run Synthesis (sentez)"
puts "   3. Run Implementation (yerlesim ve yonlendirme)"
puts "   4. Generate Bitstream (bitstream uret)"
puts "   5. Program FPGA (Hardware Manager ile)"
puts ""
puts " Alternatif (batch mod):"
puts "   launch_runs synth_1 -jobs 4"
puts "   wait_on_run synth_1"
puts "   launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "   wait_on_run impl_1"
puts "════════════════════════════════════════════════════"
