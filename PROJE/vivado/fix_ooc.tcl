# ─────────────────────────────────────────────────────
# fix_ooc.tcl — OOC Sorununu Çözme Script'i
# ─────────────────────────────────────────────────────

# Mevcut projeyi aç
open_project C:/Users/DELL/Downloads/HexaCore-V2/PROJE/vivado/hexacore_v2/hexacore_v2.xpr

# Top-level modülü kontrol et
set_property top nexys_a7_top [current_fileset]

# Synthesis'i resetle ve tekrar çalıştır
reset_run synth_1
launch_runs synth_1 -jobs 4

# Implementation'i resetle ve tekrar çalıştır
reset_run impl_1
launch_runs impl_1 -jobs 4

puts "OOC sorunu çözüldü. Synthesis ve implementation tekrar çalıştırılıyor..."