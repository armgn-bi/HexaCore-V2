# xsim_run_wdb.tcl — XSIM batch çalıştırma scripti (WDB waveform kaydı ile)
# Kullanım: xsim <snapshot> --tclbatch xsim_run_wdb.tcl

# Waveform kaydı (WDB formatı — Vivado GUI'de açılabilir)
log_wave -recursive *

# Simülasyonu sonuna kadar çalıştır
run all

# Çıkış
quit
