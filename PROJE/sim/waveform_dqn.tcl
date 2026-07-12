# ═══════════════════════════════════════════════════════════════
# Waveform TCL Script — DQN Inference Sinyalleri
# Kullanim: xsim tb_dqn_snap --gui --tclbatch waveform_dqn.tcl
# ═══════════════════════════════════════════════════════════════

create_wave_config

# ── Clock & Reset ──
add_wave /tb_dqn/clk
add_wave /tb_dqn/rstn

# ── AXI Interface ──
add_wave /tb_dqn/axi_awvalid
add_wave /tb_dqn/axi_awready
add_wave -radix hex /tb_dqn/axi_awaddr
add_wave /tb_dqn/axi_wvalid
add_wave /tb_dqn/axi_wready
add_wave -radix hex /tb_dqn/axi_wdata
add_wave /tb_dqn/axi_arvalid
add_wave /tb_dqn/axi_arready
add_wave /tb_dqn/axi_rvalid
add_wave -radix hex /tb_dqn/axi_rdata

# ── DQN Control/Status ──
add_wave /tb_dqn/dut/ctrl_enable
add_wave /tb_dqn/dut/ctrl_start
add_wave /tb_dqn/dut/core_busy
add_wave /tb_dqn/dut/core_done
add_wave /tb_dqn/dut/done_sticky
add_wave /tb_dqn/dut/wt_loaded

# ── DQN Core Internals ──
add_wave /tb_dqn/dut/u_core/state
add_wave -radix hex /tb_dqn/dut/u_core/state_in[0]
add_wave -radix hex /tb_dqn/dut/u_core/state_in[1]
add_wave -radix hex /tb_dqn/dut/u_core/state_in[2]
add_wave -radix hex /tb_dqn/dut/u_core/state_in[3]

# ── Q-Values ──
add_wave -radix decimal /tb_dqn/dut/u_core/q_val[0]
add_wave -radix decimal /tb_dqn/dut/u_core/q_val[1]
add_wave -radix decimal /tb_dqn/dut/u_core/q_val[2]
add_wave -radix decimal /tb_dqn/dut/u_core/q_val[3]

# ── Argmax & Q_max ──
add_wave -radix unsigned /tb_dqn/dut/u_core/argmax
add_wave -radix decimal /tb_dqn/dut/u_core/q_max
add_wave -radix unsigned /tb_dqn/dut/u_core/cycle_cnt

# Simulasyonu calistir
run 12us

save_wave_config dqn_waveform.wcfg
