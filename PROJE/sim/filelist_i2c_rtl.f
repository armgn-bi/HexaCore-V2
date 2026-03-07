// ─────────────────────────────────────────────────────
// filelist_i2c_rtl.f — I2C Periferal RTL kaynak dosyaları
// Fonksiyon testi için minimal bağımlılık seti
// xvlog --sv -f filelist_i2c_rtl.f  şeklinde kullanılır
// ─────────────────────────────────────────────────────

// Paket dosyaları (önce derlenmeli)
../rtl/bus/axi_pkg.sv

// AXI4-Lite Slave Bridge (axi_i2c bağımlılığı)
../rtl/bus/axi_lite_slave.sv

// I2C modülleri
../rtl/i2c/i2c_master.sv
../rtl/i2c/axi_i2c.sv
