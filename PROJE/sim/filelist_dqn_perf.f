// ─────────────────────────────────────────────────────
// filelist_dqn_perf.f — DQN Performans Testi RTL + Testbench
// xvlog --sv -f filelist_dqn_perf.f  seklinde kullanilir
// ─────────────────────────────────────────────────────

// Paket dosyalari (once derlenmeli)
../rtl/riscv_pkg.sv
../rtl/bus/axi_pkg.sv

// AXI Bus
../rtl/bus/axi_master_if.sv
../rtl/bus/axi_lite_slave.sv
../rtl/bus/axi_interconnect.sv

// DQN RTL
../rtl/dqn/dqn_core.sv
../rtl/dqn/dqn_accelerator.sv

// Performans Testbench
../tb/periph_tb/tb_dqn_performance.sv
