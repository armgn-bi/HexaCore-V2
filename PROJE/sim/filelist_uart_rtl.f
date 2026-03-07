// ─────────────────────────────────────────────────────
// filelist_uart_rtl.f — UART Periferal RTL kaynak dosyaları
// Fonksiyon testi için minimal bağımlılık seti
// xvlog --sv -f filelist_uart_rtl.f  şeklinde kullanılır
// ─────────────────────────────────────────────────────

// Paket dosyaları (önce derlenmeli)
../rtl/bus/axi_pkg.sv

// AXI4-Lite Slave Bridge (axi_uart bağımlılığı)
../rtl/bus/axi_lite_slave.sv

// UART modülleri
../rtl/uart/uart_fifo.sv
../rtl/uart/uart_tx.sv
../rtl/uart/uart_rx.sv
../rtl/uart/axi_uart.sv
