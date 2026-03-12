// ─────────────────────────────────────────────────────
// filelist_dqn_perf.f — DQN Performans Testi
// xvlog --sv -f filelist_dqn_perf.f  seklinde kullanilir
// ─────────────────────────────────────────────────────

// Paket dosyalari
../rtl/riscv_pkg.sv
../rtl/bus/axi_pkg.sv

// AXI Bus
../rtl/bus/axi_master_if.sv
../rtl/bus/axi_lite_slave.sv
../rtl/bus/axi_interconnect.sv

// DQN RTL
../rtl/dqn/dqn_core.sv
../rtl/dqn/dqn_accelerator.sv

// DQN Performans Testbench
../tb/periph_tb/tb_dqn_perf.sv
