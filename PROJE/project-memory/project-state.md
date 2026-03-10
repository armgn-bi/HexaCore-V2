# RISC-V SoC Proje Durumu (Son güncelleme: 2026-03-08)

## Genel Durum
RV32I 5-aşamalı pipeline RISC-V çekirdeği + AXI4-Lite bus altyapısı + periferaller.
Pipeline artık dahili DMEM ve AXI üzerinden tüm periferal erişimini destekliyor.
XSIM simülasyon altyapısı hazır.
- **Kapsamlı SoC sistem testi (Core→AXI→tüm periferaller): 23/23 PASS**
- **Full SoC entegrasyon testi (pipeline→AXI→periferaller): 9/9 PASS**
- **SoC entegrasyon testleri (AXI doğrudan): 46/46 PASS**
- **Core regresyon testleri: 2111/2111 PASS**
- **UART fonksiyon testi: 68/68 PASS**
- **SPI fonksiyon testi: 144/144 PASS**
- **I2C fonksiyon testi: 52/52 PASS**

## Tamamlanan İşler

### 1. AXI Bus Altyapısı (rtl/bus/)
- `axi_pkg.sv` — 5 slave (DMEM/UART/SPI/I2C/DSP), adres haritası BASE/MASK
- `axi_master_if.sv` — Pipeline MEM-stage → AXI4-Lite master bridge (FSM: IDLE→RD/WR)
- `axi_interconnect.sv` — 1-master N-slave, wr_active_q/rd_active_q latch, DECERR for no-match
- `axi_dmem_slave.sv` — AXI4-Lite→DMEM FSM (IDLE→WR_EXEC→WR_RESP / RD_EXEC→RD_RESP)
- `axi_lite_slave.sv` — Generic AXI4-Lite→register interface bridge (DSP wrapper kullanır)

### 2. DSP Filtre (rtl/dsp/)
- `dsp_filter_wrapper.sv` — AXI4-Lite register map wrapping dsphdl_FIRFilter
- MATLAB HDL Coder çıktısı Verilog dosyaları: dsphdl_FIRFilter.v, Filter.v, FilterCoef.v, vb.

### 3. UART Periferal (rtl/uart/)
- `uart_tx.sv` — UART Transmitter, 8N1, 16x oversampling baud tick, FSM: IDLE→START→DATA→STOP
- `uart_rx.sv` — UART Receiver, 8N1, 16x oversampling, 2-FF metastability sync, ortada örnekleme
- `uart_fifo.sv` — Parametrik sünkron FIFO (varsayılan 16 derinlik, 8-bit genişlik)
- `axi_uart.sv` — AXI4-Lite UART wrapper, `axi_lite_slave` bridge kullanır
  - Register map: TXDATA(0x00), RXDATA(0x04), STATUS(0x08), CTRL(0x0C), BAUD_DIV(0x10)
  - TX/RX FIFO (16 eleman), baud rate generator (16x oversampling)
  - Interrupt: `(tx_ie & tx_empty) | (rx_ie & ~rx_empty)`
  - Sticky error flags: frame_err, overrun_err (STATUS'a yazarak temizlenir)

### 4. I2C Periferal (rtl/i2c/)
- `i2c_master.sv` — I2C Master Controller, 7-bit adres, 8-bit veri, open-drain SDA/SCL
  - FSM: IDLE→START→WRITE_BIT→WRITE_ACK / READ_BIT→READ_SEND→STOP
  - 4-fazlı SCL clock divider (prescale_i ile ayarlanır)
  - Komut arayüzü: START/WRITE/READ_ACK/READ_NACK/STOP
  - 2-FF metastability sync (SDA/SCL girişleri)
- `axi_i2c.sv` — AXI4-Lite I2C wrapper, `axi_lite_slave` bridge kullanır
  - Register map: TXDATA(0x00), RXDATA(0x04), STATUS(0x08), CTRL(0x0C), PRESCALE(0x10), CMD(0x14)
  - STATUS: busy, ack_err(sticky), rx_valid, cmd_ready
  - Interrupt: `ie & (cmd_ready | ack_err)`
  - DEFAULT_PRESCALE=249 (100MHz→100kHz)

### 5. SPI Periferal (rtl/spi/)
- `spi_master.sv` — SPI Master Controller, CPOL/CPHA (Mode 0–3), MSB-first, 8-bit
  - FSM: IDLE→LEADING→TRAILING, configurable clock divider (SCK half-period = (clk_div+1) clk)
  - 4-slave active-low chip select, 2-FF MISO metastability sync
  - CPHA=0: sample on leading, shift on trailing; CPHA=1: shift on leading, sample on trailing
- `axi_spi.sv` — AXI4-Lite SPI wrapper, `axi_lite_slave` bridge kullanır
  - Register map: TXDATA(0x00), RXDATA(0x04), STATUS(0x08), CTRL(0x0C), CLK_DIV(0x10), CMD(0x14)
  - STATUS: busy(en & ~ready), rx_valid(sticky), ready
  - CTRL: en, cpol, cpha, ie, cs_sel[1:0], cs_en
  - Interrupt: `ie & rx_valid`
  - DEFAULT_CLK_DIV=49 (100MHz→1MHz)

### 6. SoC Top (rtl/top/soc_top.sv)
- Pipeline dahili DMEM + harici AXI bellek erişimi destekliyor
- Adres yönlendirme: [0x8000_0000, 0x8000_8000) → dahili DMEM; diğer tüm adresler → AXI
- AXI Master IF, pipeline'ın ext_mem_* portlarına bağlı (gerçek bağlantı, placeholder yok)
- Pipeline'da ext_stall_w sinyali AXI erişimi sırasında tüm 5 aşamayı dondurur
- ext_req_sent_q kaydı ile AXI'ye tek-cycle istek pulsu gönderilir
- **UART modülü (axi_uart) Slave 1 olarak bağlandı** — uart_tx_o, uart_rx_i, uart_irq_o
- **SPI modülü (axi_spi) Slave 2 olarak bağlandı** — spi_sck_o, spi_mosi_o, spi_miso_i, spi_ss_o[3:0]
- **I2C modülü (axi_i2c) Slave 3 olarak bağlandı** — open-drain tristate (scl_oe/sda_oe + readback)
- Tüm 5 slave gerçek modüller (DMEM/UART/SPI/I2C/DSP) — stub slave kalmadı
- Backward compat: ext_mem_ready_i=1, ext_mem_rdata_i=0 default değerleri eski TB'lerin çalışmasını sağlar

### 7. Simülasyon (sim/)
- `run_sim.ps1` — Ana PowerShell runner (compile/elaborate/sim/soc_test/clean/wave targets)
- `run_sim.bat` — Windows BAT wrapper
- `run_soc_test.ps1` — SoC test standalone runner (40/40 AXI doğrudan test)
- `run_soc_full_test.ps1` — Full SoC test runner (9/9 pipeline→AXI→periferaller)
- `gen_lsu_golden.ps1` — LSU golden log üretme scripti
- `Makefile` — GNU Make akışı (soc_test target dahil)
- `filelist_core.f`, `filelist_dsp_verilog.f`, `filelist_tb.f`, `filelist_tb_soc.f`, `filelist_tb_soc_full.f`
- `filelist_uart_rtl.f`, `filelist_tb_uart.f` — UART fonksiyon testi
- `filelist_spi_rtl.f`, `filelist_tb_spi.f` — SPI fonksiyon testi
- `run_spi_test.ps1` — SPI fonksiyon testi runner (144/144 PASS)
- `run_uart_test.ps1` — UART fonksiyon testi runner (68/68 PASS)
- `run_i2c_test.ps1` — I2C fonksiyon testi runner (52/52 PASS)
- `filelist_i2c_rtl.f`, `filelist_tb_i2c.f` — I2C fonksiyon testi
- `run_soc_sys_test.ps1` — Kapsamlı SoC sistem testi runner (23/23 PASS)
- `filelist_tb_soc_sys.f` — Kapsamlı SoC sistem testi filelist
- `xsim_run.tcl`, `xsim_run_wdb.tcl`
- `.vscode/tasks.json` — 8 VS Code task (Compile/Elaborate/Sim/Full/Check/SoC Test/Wave/Clean)
- Vivado 2025.2 yolu: `C:\AMDDesignTools\2025.2\Vivado\bin`

### 8. SoC Entegrasyon Testi (tb/soc_tb/tb_soc_integration.sv)
- AXI Master IF → Interconnect → DMEM/DSP/UART/SPI/I2C doğrudan sürer (pipeline bypass)
- UART testleri: STATUS başlangıç, CTRL R/W, BAUD_DIV R/W, TX→RX loopback
- SPI testleri: STATUS başlangıç, CTRL en+cs0, CLK_DIV R/W, TXDATA R/W, 3 full-duplex transfer (0xA5↔0xA5, 0x55↔0xCC, 0xDE↔0xAD) + çift yönlü veri doğrulama, CS deassert
- I2C testleri: STATUS başlangıç, CTRL enable, PRESCALE R/W, TXDATA R/W
- I2C transaction testi: START + WRITE(addr) + WRITE(data) + STOP → basit slave model ACK verir
- **46/46 PASS** (DMEM 13 + DSP 4 + UART 4 + SPI 14 + I2C 9 + Cross 2)
- SPI slave model: Geliştirilmiş çift-register BFM — ayrı TX/RX shift register, CPHA=1 first-shift-skip, CS kenar algılama, combinational MISO, CLK_DIV=4 (2-FF sync marjı)
- I2C slave model: 7-bit addr=0x50, 4-byte internal memory, START/STOP detect, ACK/NACK
- Debug MON bloğu `ifdef DEBUG_MON` ile korunmuş (-d DEBUG_MON ile aktifleşir)

### 10. Full SoC Entegrasyon Testi (tb/soc_tb/tb_soc_full.sv)
- **Pipeline → AXI → Periferaller uçtan uca testi** — gerçek RISC-V talimatları çalıştırır
- Hand-encoded RISC-V test programı (tb/imem_soc_full.mem, 25 talimat)
- 7 test fazı:
  1. Dahili DMEM yazma/okuma → x10=0xAB
  2. AXI DMEM yazma/okuma → x11=0x5A
  3. UART STATUS okuma → x12=0x0A
  4. SPI CTRL yazma/okuma → x13=0x41
  5. I2C CTRL yazma/okuma → x14=0x01
  6. DSP CTRL yazma/okuma → x15=0x01
  7. AXI DMEM persistence → x16=0x5A
- Halt detection: JAL x0,0 sonsuz döngü, WB commit sayacı ile tespit
- Register doğrulama: hierarchical access ile register_file değerleri kontrol edilir
- **9/9 PASS** — 69 cycle'da tamamlanır (875ns @100MHz)
- Runner: sim/run_soc_full_test.ps1, filelist: sim/filelist_tb_soc_full.f

### 14. Kapsamlı SoC Sistem Testi (tb/soc_tb/tb_soc_system.sv)
- **Pipeline → AXI → TÜM periferaller gerçek fonksiyonel test** — UART loopback, SPI transfer, I2C transaction
- Hand-encoded RISC-V test programı (tb/imem_soc_sys.mem, 113 talimat, 22+1 doğrulama)
- 8 test fazı + bonus:
  1. İç DMEM çoklu pattern (0xDEADBEEF, 0x12345678) + kalıcılık → x10,x11,x12
  2. AXI DMEM çoklu pattern (0xCAFEBABE, 0xA5A5A5A5, 0x55) + kalıcılık → x13,x14,x15,x16
  3. UART TX→RX loopback: BAUD_DIV=0, CTRL=tx+rx_en, TXDATA=0x55, delay loop, RXDATA readback → x17,x18,x19
  4. SPI Mode0 full-duplex: CLK_DIV=2, slave BFM(init=0x5A), TXDATA=0xA5, CMD=start, RXDATA=0x5A → x20,x21,x22
  5. I2C write transaction: PRESCALE=1, START+WRITE(0xA0)+WRITE(0xBB)+STOP, polling loops, ack_err=0 → x23,x24,x25
  6. DSP CTRL enable + DATA_IN=0x1234 readback → x26,x27
  7. Cross-peripheral: UART STATUS→AXI_DMEM→readback, I2C STATUS→AXI_DMEM→readback → x28,x29
  8. Hızlı periferal geçişi: AXI_DMEM write → SPI STATUS read → AXI_DMEM readback → x30,x31
  Bonus: I2C slave internal memory doğrulaması (mem[0]=0xBB)
- BFM'ler:
  - UART: Combinational loopback (uart_tx_o → uart_rx_i)
  - SPI: Mode 0 slave shift register (init=0x5A), negedge SCK shift, posedge SCK sample
  - I2C: 8-state FSM slave (addr=0x50), open-drain SDA, START/STOP detect, ACK, 4-byte memory
- Polling loops: I2C cmd_ready polling (BEQ+LW+ANDI), firmware delay loops (BNE counter)
- **23/23 PASS** — 882 cycle'da tamamlanır (~9μs @100MHz)
- Runner: sim/run_soc_sys_test.ps1, filelist: sim/filelist_tb_soc_sys.f
- **Not:** SPI CLK_DIV=2 kullanılır — 2-FF MISO senkronizörüne 3 clock marj tanır (CLK_DIV<2'de sync gecikmesi veri hatasına yol açar)

### 9. Golden Log Dosyaları (tb/)
- `base_test.golden_clean.log.txt` ✅
- `book_test.golden_clean.log.txt` ✅
- `bubble_sort.golden_clean.log.txt` ✅
- `lsu.golden_clean.log.txt` ✅ (gen_golden.sv ile üretildi)

## Kritik Bugfix Geçmişi

### Pipeline ext_stall halt detection (ÇÖZÜLDÜ)
- **Problem:** JAL x0,0 sonsuz döngüsünde pipeline sürekli flush yapıyor → WB'de consecutive PC match 3'e ulaşamıyor
- **Fix:** TB'de ardışık yerine toplam WB commit sayacı kullanıldı (halt_count >= 3)

### Pipeline AXI re-trigger (ÇÖZÜLDÜ)
- **Problem:** AXI Master IF IDLE'a dönüp pipeline hala stall'dayken mem_read/write aktif → yeni transaction başlatıyordu
- **Fix:** `ext_req_sent_q` register ile tek-cycle istek pulsu, ready=1 gelene kadar bekle

### soc_top implicit wire declaration (ÇÖZÜLDÜ)
- **Problem:** Pipeline instance, core_mem_* sinyallerini kullanmadan önce tanımlanmamıştı → XSIM implicit declaration warning
- **Fix:** Sinyal tanımları pipeline instance'ından önce taşındı

### axi_master_if.sv ready_o Race Condition (ÇÖZÜLDÜ)
- **Problem:** TB taskleri `@(posedge clk)` ile sinyal sürüyordu → DUT'un `always_ff @(posedge clk_i)` ile yarış durumu. `ready_o=1` IDLE'da mem_read/mem_write assertken bile 1 kalıyordu → task hemen dönüyordu.
- **RTL Fix:** `S_IDLE`'da `ready_o=0` when `mem_read_i||mem_write_i` (combinational stall)
- **TB Fix:** Task'lar `@(negedge clk)` ile sinyal sürer → posedge'den önce stable

### axi_master_if.sv aw_fire/w_fire (ÇÖZÜLDÜ)
- `aw_fire`/`w_fire` sinyalleri `always_comb` içinden module-level'a taşındı (XSIM assign-inside-always_comb hatası)

### axi_uart.sv Baud Counter Overflow (ÇÖZÜLDÜ)
- **Problem:** `baud_cnt_q == baud_div_q` karşılaştırması kullanılıyordu. BAUD_DIV runtime'da küçültüldüğünde (ör. 53→0) counter mevcut değer > yeni divisor oluyor, eşleşme sağlanamıyor → 65536 cycle boyunca tick üretilmiyor → TX donuyor.
- **RTL Fix:** `baud_cnt_q >= baud_div_q` kullanıldı (hem reset hem tick karşılaştırmasında). Divisor küçüldüğünde counter anında sıfırlanır.

### axi_uart.sv rx_data implicit declaration (ÇÖZÜLDÜ)
- `rx_data` sinyali RX FIFO instance'ından önce kullanılıp sonra tanımlanıyordu → XSIM implicit declaration uyarısı. Tanım FIFO'dan önce taşındı.

### i2c_master.sv rx_data_o shift hatası (ÇÖZÜLDÜ)
- **Problem:** `S_READ_BIT` state'inde, phase 10'da `shift_q <= {shift_q[6:0], sda_sync2}` ile 8 bit toplanıyor. Ardından phase 11'de `rx_data_o <= {shift_q[6:0], sda_sync2}` yapılıyordu. Ancak NBA semantiği nedeniyle `shift_q` zaten 8 bit'in tamamını içeriyor → MSB düşürülüp aynı bit tekrar ekleniyor.
- **Örnek:** 0xA1 (10100001) → `{shift_q[6:0], sda_sync2}` = 01000011 = 0x43
- **RTL Fix:** `rx_data_o <= shift_q;` — shift register'daki tam 8 bit doğrudan kullanıldı.

## Adres Haritası
| Bölge      | Başlangıç    | Bitiş        | Boyut | Durum              |
|------------|-------------|-------------|-------|--------------------|
| IMEM       | 0x8000_0000 | 0x8000_FFFF | 64KB  | Dahili (pipeline)  |
| İç DMEM    | 0x8000_0000 | 0x8000_7FFF | 32KB  | Dahili (pipeline)  |
| AXI DMEM   | 0x8001_0000 | 0x8001_7FFF | 32KB  | AXI Slave ✅       |
| UART       | 0x4000_0000 | 0x4000_00FF | 256B  | AXI Slave ✅       |
| SPI        | 0x4000_0100 | 0x4000_01FF | 256B  | AXI Slave ✅       |
| I2C        | 0x4000_0200 | 0x4000_02FF | 256B  | AXI Slave ✅       |
| DSP        | 0x4000_1000 | 0x4000_1FFF | 4KB   | AXI Slave ✅       |

**Adres yönlendirme (pipeline):** [0x8000_0000, 0x8000_8000) → dahili DMEM; diğerleri → AXI Master IF

## Sıradaki İşler (TODO)

### Yüksek Öncelik
1. ~~**Pipeline → AXI entegrasyonu:**~~ ✅ Tamamlandı — ext_mem_* portları, adres yönlendirme, stall mekanizması, 9/9 full SoC test
2. ~~**UART modülü (rtl/uart/):**~~ ✅ Tamamlandı
3. ~~**SPI Master (rtl/spi/):**~~ ✅ Tamamlandı — AD SPI spec uyumlu, CPOL/CPHA, clock divider, multi-slave CS, 144/144 fonksiyon + 46/46 SoC test
4. ~~**I2C Master (rtl/i2c/):**~~ ✅ Tamamlandı

### 11. UART Fonksiyon Testi (tb/periph_tb/tb_uart.sv)
- axi_uart modülünü doğrudan AXI4-Lite sinyalleriyle sürer (pipeline/interconnect bypass)
- Loopback modu (tx_o→rx_i) + davranışsal UART TX BFM + RX bit-level monitor
- 12 test grubu, 68 test:
  1. Reset değerleri (STATUS=0x0A, CTRL=0, BAUD_DIV=0)
  2. Register R/W (CTRL tüm bitler, BAUD_DIV, TXDATA write-only)
  3. Tek byte TX→RX loopback (0x55, 0xAA, 0xA5)
  4. Data pattern loopback (0x00, 0xFF, 0x01, 0x80, 0x5A, 0x42, 0xDE, 0x7E)
  5. Çoklu byte ardışık loopback (4 byte FIFO sıralaması)
  6. TX FIFO bayrakları (tx_full, tx_empty, 16-byte dolum+boşaltma, RX FIFO sıralı doğrulama)
  7. Interrupt doğrulama (tx_ie, rx_ie, enable/disable)
  8. Frame hatası enjeksiyonu (BFM: bozuk stop bit → sticky flag + clear)
  9. Overrun hatası (BFM: 16+1 byte → overrun flag + clear)
  10. Farklı baud rate (BAUD_DIV=1, BAUD_DIV=2)
  11. TX/RX enable kontrolü (devre dışı/etkin geçiş)
  12. Bit-seviyeli TX doğrulama (RX monitor ile)
- **68/68 PASS** — ~24.5us simülasyon süresi
- Runner: sim/run_uart_test.ps1
- Filelist: sim/filelist_uart_rtl.f, sim/filelist_tb_uart.f

### Orta Öncelik
### 12. SPI Fonksiyon Testi (tb/periph_tb/tb_spi.sv) — AD Spec Uyumlu
- Analog Devices SPI spesifikasyonuna göre doğrulanmış (https://www.analog.com/en/resources/analog-dialogue/articles/introduction-to-spi-interface.html)
- axi_spi modülünü doğrudan AXI4-Lite sinyalleriyle sürer (pipeline/interconnect bypass)
- Geliştirilmiş çift-register Slave BFM: ayrı TX/RX shift registerları, CPHA=1 first-shift-skip, CS kenar algılama, combinational MISO
- CLK_DIV=4 (half-period=5 clocks) — 2-FF MISO senkronizör propagasyon gecikmesi (4 clock) < half-period
- 13 test grubu, 144 test (tüm SPI modlarında 12 pattern full-duplex doğrulama):
  1. Reset değerleri (STATUS, CTRL, CLK_DIV, CMD, RXDATA) — 5 test
  2. Register R/W (CTRL, CLK_DIV, TXDATA, STATUS, CMD) — 8 test
  3. Mode 0 (CPOL=0,CPHA=0) full-duplex — 12 pattern × 2 yön = 24 test
  4. Mode 1 (CPOL=0,CPHA=1) full-duplex — 12 pattern × 2 yön = 24 test
  5. Mode 2 (CPOL=1,CPHA=0) full-duplex — 12 pattern × 2 yön = 24 test
  6. Mode 3 (CPOL=1,CPHA=1) full-duplex — 12 pattern × 2 yön = 24 test
  7. Çoklu byte ardışık transfer (5 byte sıralı) — 5 test
  8. rx_valid bayrağı + STATUS temizleme (sticky davranış) — 5 test
  9. Interrupt doğrulama (ie & rx_valid, enable/disable) — 6 test
  10. Chip select kontrol (CS0-CS3 + CS1 transfer) — 8 test
  11. Farklı CLK_DIV (7, 15, restore 4) — 6 test
  12. Enable kontrolü (ready, CS durumu) — 3 test
  13. Busy bayrağı doğrulama — 3 test
- Data patternleri (her mod için): 0xA5↔0x5A, 0x00↔0xFF, 0xFF↔0x00, 0x01↔0x80, 0x80↔0x01, 0xAA↔0x55, 0x55↔0xAA, 0x3C↔0xC3, 0xDE↔0xAD, 0xBE↔0xEF, 0xCA↔0xFE, 0x12↔0x34
- **144/144 PASS** — ~88us simülasyon süresi
- Runner: sim/run_spi_test.ps1
- Filelist: sim/filelist_spi_rtl.f, sim/filelist_tb_spi.f

### 13. I2C Fonksiyon Testi (tb/periph_tb/tb_i2c.sv)
- axi_i2c modülünü doğrudan AXI4-Lite sinyalleriyle sürer (pipeline/interconnect bypass)
- Davranışsal I2C Slave BFM (7-bit addr=0x50, 8-byte internal memory, open-drain modelleme)
- 14 test grubu, 52 test:
  1. Reset değerleri (TXDATA=0, RXDATA=0, STATUS=0, CTRL=0, PRESCALE=DEFAULT)
  2. Register R/W (TXDATA, CTRL, PRESCALE, CMD, STATUS cmd_ready, RXDATA read-only)
  3. I2C Write tek byte (slave bellek doğrulama, ack_err kontrolü)
  4. I2C Write çoklu byte (3 byte ardışık yazma)
  5. I2C Read tek byte (slave→master veri transferi)
  6. I2C Read çoklu byte (3 byte ardışık okuma, byte-boundary timing)
  7. Data pattern (0x00, 0xFF, 0x55, 0xAA)
  8. ACK error (yanlış adres → ack_err sticky flag)
  9. Sticky ack_err + DUT reset clear (wrapper'daki sticky flag sadece reset ile temizlenir)
  10. rx_valid flag + RXDATA okuma ile temizleme
  11. Interrupt doğrulama (ie & cmd_ready, ie & ack_err)
  12. PRESCALE değişiklikleri (2, 3)
  13. Enable kontrolü (devre dışı/etkin geçiş)
  14. Busy/cmd_ready bayrakları
- Slave BFM: 11 state FSM (IDLE, ADDR_BIT, ADDR_ACK1/2, WR_BIT, WR_ACK1/2, RD_BIT, RD_RELEASE, RD_ACK_WAIT, RD_NEXT_PREP, STOP_WAIT)
- **52/52 PASS** — ~9.9μs simülasyon süresi
- Runner: sim/run_i2c_test.ps1
- Filelist: sim/filelist_i2c_rtl.f, sim/filelist_tb_i2c.f
- **Not:** Test sırasında i2c_master.sv'de rx_data_o shift hatası bulunup düzeltildi (bkz. Bugfix Geçmişi)

### Orta Öncelik
5. **Periferal testbench'leri:** ~~`tb/periph_tb/tb_uart.sv`~~✅ ~~`tb_spi.sv`~~✅ ~~`tb_i2c.sv`~~✅
6. **RISC-V firmware (sw/):** `startup.S`, `linker.ld`, `main.c`, `Makefile`
7. **FPGA constraints:** `constraints/pins.xdc`

### Düşük Öncelik
8. `dmem.sv` içindeki `logic [31:0] temp;` always_comb'da — çalışıyor ama stil olarak tartışmalı

## Dizin Yapısı
```
rtl/
  core dosyaları (alu, pipeline, register_file, dmem, imem, vb.)
  bus/ (axi_pkg, axi_master_if, axi_interconnect, axi_dmem_slave, axi_lite_slave)
  dsp/ (dsp_filter_wrapper, MATLAB HDL Coder Verilog'ları)
  top/ (soc_top.sv)
  uart/ (axi_uart, uart_tx, uart_rx, uart_fifo)
  i2c/  (axi_i2c, i2c_master)
  spi/  (axi_spi, spi_master)
tb/
  tb_rv.sv (4-test pipeline scoreboard)
  gen_golden.sv (golden log üreteci)
  imem_soc_full.mem (full SoC test programı — 25 RISC-V talimatı)
  soc_tb/tb_soc_integration.sv (40-test AXI entegrasyon + SPI/I2C slave model)
  soc_tb/tb_soc_full.sv (9-test full SoC pipeline→AXI→periferaller)
  *.mem, *.golden_clean.log.txt (test verileri — TEK KAYNAK)
sim/
  Build script'ler ve filelist'ler (mem/txt dosyaları burada TUTULMAZ, tb/'den kopyalanır)
```

## Konvansiyonlar
- SystemVerilog (IEEE 1800-2017), `timescale 1ns/1ps`
- Active-low async reset: `rstn_i`
- Signal suffix: `_i` input, `_o` output, pipeline stage: F/D/E/M/W
- Parametre: UPPER_SNAKE_CASE
- AXI: ARM AMBA standard naming
- `always_ff` sequential, `always_comb` combinational, `always_latch` KULLANMA
- `logic` tipi (reg/wire değil)
- Paket: `import riscv_pkg::*;`, `import axi_pkg::*;`
