// ─────────────────────────────────────────────────────
// filelist_spi_rtl.f — SPI Periferal RTL kaynak dosyaları
// Fonksiyon testi için minimal bağımlılık seti
// xvlog --sv -f filelist_spi_rtl.f  şeklinde kullanılır
// ─────────────────────────────────────────────────────

// Paket dosyaları (önce derlenmeli)
../rtl/bus/axi_pkg.sv

// AXI4-Lite Slave Bridge (axi_spi bağımlılığı)
../rtl/bus/axi_lite_slave.sv

// SPI modülleri
../rtl/spi/spi_master.sv
../rtl/spi/axi_spi.sv
