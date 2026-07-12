# ═══════════════════════════════════════════════════════════════
# Waveform TCL Script — Pipeline Sinyalleri
# XSIM GUI'de otomatik sinyal ekleme ve waveform kaydi
# Kullanim: xsim tb_rv_all_snap --gui --tclbatch waveform_pipeline.tcl
# ═══════════════════════════════════════════════════════════════

# Waveform penceresini ac
create_wave_config

# ── Clock & Reset ──
add_wave /tb_rv_all/dut1/clk_i
add_wave /tb_rv_all/dut1/rstn_i

# ── Program Counter (Pipeline asamalari) ──
add_wave -radix hex /tb_rv_all/dut1/pcF
add_wave -radix hex /tb_rv_all/dut1/instrF

# ── ID Stage ──
add_wave -radix hex /tb_rv_all/dut1/instrD
add_wave -radix unsigned /tb_rv_all/dut1/u_ctrl/opcode
add_wave /tb_rv_all/dut1/reg_writeD
add_wave /tb_rv_all/dut1/mem_readD
add_wave /tb_rv_all/dut1/mem_writeD

# ── EX Stage ──
add_wave -radix hex /tb_rv_all/dut1/aluY
add_wave -radix hex /tb_rv_all/dut1/immE

# ── MEM Stage ──
add_wave /tb_rv_all/dut1/mem_readM
add_wave /tb_rv_all/dut1/mem_writeM
add_wave -radix hex /tb_rv_all/dut1/aluY_M

# ── WB Stage ──
add_wave /tb_rv_all/dut1/reg_writeW_r
add_wave -radix hex /tb_rv_all/dut1/resultW

# ── Hazard & Forwarding ──
add_wave /tb_rv_all/dut1/u_hazard/stallF
add_wave /tb_rv_all/dut1/u_hazard/stallD
add_wave /tb_rv_all/dut1/u_hazard/flushD
add_wave /tb_rv_all/dut1/u_hazard/flushE

# ── Register File (x1-x5) ──
add_wave -radix hex /tb_rv_all/dut1/u_rf/regs[1]
add_wave -radix hex /tb_rv_all/dut1/u_rf/regs[2]
add_wave -radix hex /tb_rv_all/dut1/u_rf/regs[3]
add_wave -radix hex /tb_rv_all/dut1/u_rf/regs[4]
add_wave -radix hex /tb_rv_all/dut1/u_rf/regs[5]

# Simulasyonu calistir
run 500ns

# WDB olarak kaydet
save_wave_config pipeline_waveform.wcfg
