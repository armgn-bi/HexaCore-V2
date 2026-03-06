# xsim_run.tcl — XSIM batch çalıştırma scripti
# VCD kaydi ile simulasyon
# Kullanim: xsim <snapshot> --tclbatch xsim_run.tcl

# Waveform kaydı (opsiyonel — VCD formatı)
# open_vcd dump.vcd
# log_vcd *

# Simülasyonu sonuna kadar çalıştır
run all

# VCD kapat
# close_vcd

# Çıkış
quit
