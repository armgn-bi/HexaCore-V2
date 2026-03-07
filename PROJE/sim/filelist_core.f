// ─────────────────────────────────────────────────────
// filelist_core.f — RISC-V Core + SoC RTL kaynak dosyaları
// xvlog --sv -f filelist_core.f  şeklinde kullanılır
// ─────────────────────────────────────────────────────

// Paket dosyaları (önce derlenmeli)
../rtl/riscv_pkg.sv
../rtl/bus/axi_pkg.sv

// RISC-V Core
../rtl/alu.sv
../rtl/alu_control.sv
../rtl/main_control.sv
../rtl/register_file.sv
../rtl/imm_gen.sv
../rtl/imem.sv
../rtl/dmem.sv
../rtl/branch_compare.sv
../rtl/forwarding_unit.sv
../rtl/hazard_unit.sv
../rtl/riscv_pipeline.sv

// AXI Bus
../rtl/bus/axi_master_if.sv
../rtl/bus/axi_lite_slave.sv
../rtl/bus/axi_dmem_slave.sv
../rtl/bus/axi_interconnect.sv

// DSP (SystemVerilog wrapper)
../rtl/dsp/dsp_filter_wrapper.sv

// UART
../rtl/uart/uart_fifo.sv
../rtl/uart/uart_tx.sv
../rtl/uart/uart_rx.sv
../rtl/uart/axi_uart.sv

// SPI
../rtl/spi/spi_master.sv
../rtl/spi/axi_spi.sv

// I2C
../rtl/i2c/i2c_master.sv
../rtl/i2c/axi_i2c.sv

// SoC Top
../rtl/top/soc_top.sv
