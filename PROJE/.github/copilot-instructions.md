# Copilot Instructions — RISC-V SoC with AXI Bus, Peripherals, DSP & DQN

## 1. Projeye Genel Bakış

Bu proje, **RV32I 5-aşamalı pipeline RISC-V işlemci çekirdeği** etrafına inşa edilen bir **SoC (System-on-Chip)** tasarımıdır. İşlemci çekirdeği AXI4 bus arayüzü üzerinden aşağıdaki periferal ve hızlandırıcı modüllere bağlanacaktır:

| Modül                | Arayüz               | Açıklama                                             |
| -------------------- | -------------------- | ---------------------------------------------------- |
| **UART**             | AXI4-Lite Slave      | Seri haberleşme (TX/RX), FIFO destekli               |
| **SPI Master**       | AXI4-Lite Slave      | SPI protokolü (CPOL/CPHA yapılandırılabilir)         |
| **I2C Master**       | AXI4-Lite Slave      | I2C protokolü (7-bit adres)                          |
| **DSP Filtre**       | AXI4-Lite            | MATLAB HDL Coder çıktısı FIR filtre                  |
| **DQN Hızlandırıcı** | AXI4-Lite Slave      | DQN inference donanım hızlandırıcısı (4→16→4, Q1.15) |
| **DMEM**             | AXI4-Lite Slave      | 32 KB veri belleği                                   |
| **IMEM**             | Dahili (salt okunur) | 64 KB talimat belleği                                |

---

## 2. Mevcut İşlemci Çekirdeği Mimarisi

### 2.1 Temel Özellikler

- **ISA**: RV32I (32-bit tamsayı komut seti)
- **Pipeline**: 5 aşama — IF → ID → EX → MEM → WB
- **Hazard handling**: Load-use stall (hazard_unit), EX/MEM & MEM/WB forwarding (forwarding_unit)
- **Branch resolution**: EX aşamasında (1-cycle branch penalty, flush ile)
- **Bellek base adresi**: `0x8000_0000`
- **Veri genişliği**: `XLEN = 32`

### 2.2 Mevcut RTL Dosya Haritası

```
rtl/
├── riscv_pkg.sv          # Paket: XLEN, privilege seviyeleri, CSR tanımları
├── riscv_pipeline.sv     # Üst modül: pipeline datapath + kontrol
├── alu.sv                # ALU: ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU
├── alu_control.sv        # ALU kontrol decoder (opcode + funct3 + funct7b5)
├── main_control.sv       # Ana kontrol birimi (opcode → kontrol sinyalleri)
├── register_file.sv      # 32×32-bit register file (x0 = 0 sabiti)
├── imm_gen.sv            # Immediate üreteci (I/S/B/U/J tipleri)
├── imem.sv               # Instruction memory (ROM, $readmemh)
├── dmem.sv               # Data memory (byte-addressable, LB/LH/LW/LBU/LHU)
├── branch_compare.sv     # Branch karşılaştırma (BEQ/BNE/BLT/BGE/BLTU/BGEU)
├── forwarding_unit.sv    # Data forwarding MUX kontrol
└── hazard_unit.sv        # Load-use hazard detection + stall/flush
```

### 2.3 Pipeline Sinyal Akışı (Özet)

```
IF:  pcF → IMEM → instrF
ID:  instrD → main_control, register_file, imm_gen, hazard_unit
EX:  ALU(srcA, srcB), branch_compare → pcSrcE, pcTargetE
MEM: DMEM read/write (aluY_M = adres, storeDataM = veri)
WB:  result_W = ALU | MEM | PC+4 → register_file write-back
```

---

## 3. Hedef SoC Mimarisi

### 3.1 Bus Topolojisi

```
                    ┌──────────────┐
                    │  RISC-V Core │
                    │  (AXI Master)│
                    └──────┬───────┘
                           │ AXI4 / AXI4-Lite
                    ┌──────┴───────┐
                    │  AXI         │
                    │  Interconnect│
                    └──┬──┬──┬──┬──┘
                       │  │  │  │
            ┌──────────┘  │  │  └──────────┐
            │             │  │             │
     ┌──────┴──────┐ ┌───┴──┴───┐  ┌──────┴──────┐
     │   DMEM      │ │  UART    │  │   SPI       │
     │ AXI4 Slave  │ │ AXI4-L   │  │  AXI4-L     │
     └─────────────┘ └──────────┘  └─────────────┘
                          │
                   ┌──────┴──────┐  ┌─────────────┐
                   │   I2C       │  │  DSP Filter  │
                   │  AXI4-L     │  │ AXI4-Stream  │
                   └─────────────┘  └─────────────┘
```

### 3.2 Adres Haritası (Memory Map)

| Bölge | Başlangıç     | Bitiş         | Boyut | Açıklama                   |
| ----- | ------------- | ------------- | ----- | -------------------------- |
| IMEM  | `0x8000_0000` | `0x8000_FFFF` | 64 KB | Instruction Memory (RO)    |
| DMEM  | `0x8001_0000` | `0x8001_7FFF` | 32 KB | Data Memory (RW)           |
| UART  | `0x4000_0000` | `0x4000_00FF` | 256 B | UART Register Space        |
| SPI   | `0x4000_0100` | `0x4000_01FF` | 256 B | SPI Register Space         |
| I2C   | `0x4000_0200` | `0x4000_02FF` | 256 B | I2C Register Space         |
| DSP   | `0x4000_1000` | `0x4000_1FFF` | 4 KB  | DSP Filtre Kontrol/Data    |
| DQN   | `0x4000_2000` | `0x4000_2FFF` | 4 KB  | DQN Inference Hızlandırıcı |

---

## 4. Kodlama Kuralları ve Konvansiyonlar

### 4.1 Dil ve Sentez

- **Dil**: SystemVerilog (IEEE 1800-2017)
- **Sentez hedefi**: FPGA (Xilinx / Intel) — latch-free, sentezlenebilir yapılar
- **Timescale**: `` `timescale 1ns / 1ps `` (tüm dosyalarda)
- **Paket kullanımı**: Tüm modüller `import riscv_pkg::*;` ile başlamalı

### 4.2 İsimlendirme Kuralları

- **Modül isimleri**: `snake_case` → `axi_uart`, `dsp_fir_filter`, `axi_interconnect`
- **Sinyal isimleri**: `snake_case` + yön son eki:
  - `_i` = input, `_o` = output, `_io` = inout
  - Pipeline aşama son ekleri: `F` (Fetch), `D` (Decode), `E` (Execute), `M` (Memory), `W` (Writeback)
- **Parametre isimleri**: `UPPER_SNAKE_CASE` → `AXI_DATA_WIDTH`, `FIFO_DEPTH`
- **AXI sinyalleri**: ARM AMBA spesifikasyonundaki standart isimlendirmeyi kullan:
  - `axi_awaddr`, `axi_awvalid`, `axi_awready`, `axi_wdata`, `axi_wstrb`, `axi_wvalid`, `axi_wready`
  - `axi_araddr`, `axi_arvalid`, `axi_arready`, `axi_rdata`, `axi_rvalid`, `axi_rready`, `axi_rresp`
  - `axi_bresp`, `axi_bvalid`, `axi_bready`
- **Dosya isimleri**: Modül ismiyle birebir aynı → `axi_uart.sv` modülü `axi_uart.sv` dosyasında

### 4.3 Sıfırlama ve Saat

- **Active-low asenkron reset**: `rstn_i` (mevcut çekirdekle uyumlu)
- **Tek saat domain**: `clk_i` — tüm modüller aynı clock domain'de
- **Reset sonrası varsayılan değerler**: Tüm çıkışlar `'0` olmalı

### 4.4 Kod Yapısı

- Her modül kendi `.sv` dosyasında
- `always_ff` yalnızca sequential logic için, `always_comb` yalnızca combinational logic için
- `always_latch` kullanma — latch oluşturmaktan kaçın
- `unique case` / `unique0 case` kullanarak sentez aracı uyarılarını minimize et
- `logic` tipi kullan, `reg`/`wire` yerine (SystemVerilog standardı)

---

## 5. AXI Arayüz Tasarım Kuralları

### 5.1 AXI4-Lite (Periferaller için)

- **Veri genişliği**: 32-bit (XLEN ile uyumlu)
- **Adres genişliği**: 32-bit
- **Burst desteği yok** — tek transfer
- **Yazma kanalları**: AW (adres) + W (veri) + B (yanıt)
- **Okuma kanalları**: AR (adres) + R (veri + yanıt)
- Her periferal için ayrı bir `axi_lite_slave` wrapper modülü oluştur

### 5.2 AXI4-Stream (DSP Filtre için)

- **TDATA genişliği**: Filtre katsayı genişliğine göre (16-bit / 32-bit)
- **TVALID / TREADY** handshake
- **TLAST**: Frame sonu işareti
- DSP modülü hem AXI4-Lite (konfigürasyon) hem AXI4-Stream (veri akışı) arayüzüne sahip olacak

### 5.3 AXI Interconnect

- **1 Master (RISC-V Core) → N Slave** topolojisi
- Adres decoder'ı memory map'e göre yönlendirme yapacak
- Round-robin veya fixed-priority arbitration (tek master olduğu için basit decoder yeterli)

---

## 6. Periferal Modül Gereksinimleri

### 6.1 UART (`axi_uart.sv`)

- Baud rate yapılandırılabilir (register üzerinden divisor ayarı)
- TX ve RX FIFO (derinlik parametrik, varsayılan: 16)
- Register haritası: `TX_DATA`, `RX_DATA`, `STATUS`, `CONTROL`, `BAUD_DIV`
- Interrupt çıkışı: `uart_irq_o` (RX FIFO dolu değil/TX FIFO boş)

### 6.2 SPI Master (`axi_spi.sv`)

- CPOL/CPHA yapılandırılabilir
- Clock divider (SCK frekansı ayarlanabilir)
- 8-bit veya 16-bit transfer desteği
- Chip-select (`ss_o`) çıkışı (birden fazla slave desteği)
- Register haritası: `TX_DATA`, `RX_DATA`, `CONTROL`, `STATUS`, `CLK_DIV`

### 6.3 I2C Master (`axi_i2c.sv`)

- Standard mode (100 kHz) ve Fast mode (400 kHz)
- 7-bit adres desteği (10-bit opsiyonel)
- Start/Stop/ACK/NACK koşulları
- Register haritası: `TX_DATA`, `RX_DATA`, `CONTROL`, `STATUS`, `PRESCALER`, `ADDR`

### 6.4 DSP Filtre Modülü (`dsp_filter.sv`)

- MATLAB Filter Designer'dan export edilen katsayıları kullanacak
- Katsayılar `.mem` dosyasından veya parametre olarak yüklenecek
- Fixed-point aritmetik (Q-format, örneğin Q1.15 veya Q3.13)
- AXI4-Lite: kontrol/durum register'ları, katsayı yükleme
- AXI4-Stream: giriş (ADC sample) ve çıkış (filtrelenmiş sample)
- Parametrik: `NUM_TAPS`, `COEFF_WIDTH`, `DATA_WIDTH`, `FRAC_BITS`

---

## 7. Dizin Yapısı (Hedef)

```
PROJE/
├── rtl/
│   ├── core/                    # RISC-V çekirdeği (mevcut dosyalar)
│   │   ├── riscv_pkg.sv
│   │   ├── riscv_pipeline.sv
│   │   ├── alu.sv
│   │   ├── alu_control.sv
│   │   ├── main_control.sv
│   │   ├── register_file.sv
│   │   ├── imm_gen.sv
│   │   ├── imem.sv
│   │   ├── dmem.sv
│   │   ├── branch_compare.sv
│   │   ├── forwarding_unit.sv
│   │   └── hazard_unit.sv
│   ├── bus/                     # AXI bus altyapısı
│   │   ├── axi_pkg.sv          # AXI parametreleri ve typedef'ler
│   │   ├── axi_master_if.sv    # Core → AXI master bridge
│   │   ├── axi_interconnect.sv # Adres decoder + MUX
│   │   └── axi_lite_slave.sv   # Genel AXI-Lite slave wrapper
│   ├── periph/                  # Periferaller
│   │   ├── axi_uart.sv
│   │   ├── uart_tx.sv
│   │   ├── uart_rx.sv
│   │   ├── uart_fifo.sv
│   │   ├── axi_spi.sv
│   │   ├── spi_master.sv
│   │   ├── axi_i2c.sv
│   │   └── i2c_master.sv
│   ├── dsp/                     # DSP modülleri
│   │   ├── dsp_filter_wrapper.sv # Üst modül (AXI-Lite wrapper)
│   │   ├── dsphdl_FIRFilter.v   # MATLAB HDL Coder FIR filtre
│   │   └── *.v                  # Systolic filtre alt modülleri
│   ├── dqn/                     # DQN hızlandırıcı
│   │   ├── dqn_core.sv          # DQN inference motoru (4→16→4, Q1.15)
│   │   └── dqn_accelerator.sv  # AXI4-Lite DQN wrapper
│   └── top/
│       ├── soc_top.sv          # SoC üst modül (her şeyi bağlar)
│       └── nexys_a7_top.sv     # FPGA üst modül (Nexys A7-100T)
├── tb/
│   ├── core_tb/                 # Mevcut çekirdek testleri
│   │   ├── tb_rv.sv
│   │   ├── dmem.mem
│   │   ├── imem_base.mem
│   │   ├── imem_book.mem
│   │   ├── imem_bubble.mem
│   │   └── imem_lsu.mem
│   ├── periph_tb/               # Periferal unit testleri
│   │   ├── tb_uart.sv
│   │   ├── tb_spi.sv
│   │   ├── tb_i2c.sv
│   │   ├── tb_dqn.sv               # DQN AXI entegrasyon testi (27/27 PASS)
│   │   ├── tb_dqn_core_standalone.sv # DQN core standalone test (24/24 PASS)
│   │   └── tb_dqn_performance.sv    # DQN performans karşılaştırması (13/13 PASS)
│   ├── dsp_tb/                  # DSP testleri
│   │   ├── tb_dsp_filter.sv
│   │   └── test_samples.mem
│   └── soc_tb/                  # SoC entegrasyon testi
│       └── tb_soc.sv
├── sw/                          # RISC-V firmware (C/ASM)
│   ├── startup.S
│   ├── linker.ld
│   ├── main.c
│   └── Makefile
├── matlab/                      # MATLAB Filter Designer dosyaları
│   ├── filter_design.m
│   ├── export_coeffs.m
│   └── coeffs_fixedpoint.txt
├── constraints/                 # FPGA kısıtları
│   └── pins.xdc
├── docs/
│   └── memory_map.md
└── .github/
    └── copilot-instructions.md
```

---

## 8. Core → AXI Master Bridge Tasarım Notları

Mevcut `riscv_pipeline.sv` modülünün bellek arayüzü:

- `mem_read_i`, `mem_write_i`, `mem_size_i`, `mem_unsigned_i`
- `addr_i` (32-bit), `wdata_i` (32-bit), `rdata_o` (32-bit)

Bu sinyaller bir **AXI Master Bridge** (`axi_master_if.sv`) ile AXI4/AXI4-Lite protokolüne dönüştürülecek:

1. **Write işlemi**: `mem_write` → AW channel (adres) + W channel (veri + strobe) → B channel (yanıt bekleme)
2. **Read işlemi**: `mem_read` → AR channel (adres) → R channel (veri alma)
3. **Write strobe (`wstrb`)**: `mem_size` değerine göre byte enable oluştur:
   - `2'b00` (byte) → `4'b0001 << addr[1:0]`
   - `2'b01` (half) → `4'b0011 << addr[1:0]`
   - `2'b10` (word) → `4'b1111`
4. **Pipeline stall**: AXI transaction tamamlanana kadar pipeline'ı durdur (`stallF`, `stallD`)

---

## 9. DSP Filtre — MATLAB Entegrasyon Akışı

1. **MATLAB Filter Designer** ile filtre tasarla (FIR/IIR, düşük/yüksek/bant geçiren)
2. Katsayıları fixed-point'e çevir: `fi(coeffs, 1, 16, 15)` → Q1.15 formatı
3. Hex formatında export et → `coeffs.mem`
4. SystemVerilog'da `$readmemh("coeffs.mem", coeff_rom)` ile yükle
5. MAC (Multiply-Accumulate) yapısı: `acc += sample[n-k] * coeff[k]`
6. AXI4-Stream üzerinden sample girişi, filtrelenmiş çıkış

---

## 10. Simülasyon ve Doğrulama

### 10.1 Araçlar

- **Simülasyon**: Verilator, ModelSim/QuestaSim veya Vivado XSIM
- **Waveform**: GTKWave veya Vivado waveform viewer
- **Linting**: Verilator `--lint-only`, Vivado elaboration

### 10.2 Test Stratejisi

1. **Birim testler**: Her periferal ve DSP/DQN modülü bağımsız test edilecek
2. **Entegrasyon testi**: `soc_top` altında tüm modüller birlikte test edilecek
3. **Performans testleri**: DQN hızlandırıcı labirent çözümünde **129x–776x** hızlanma sağladığı doğrulandı
4. **Firmware testi**: RISC-V C kodu ile periferallere register erişimi test edilecek
5. **Mevcut çekirdek testleri korunacak**: `tb_rv.sv` ve golden log karşılaştırmaları

**Güncel Test Durumu (13 Mart 2026 — Vivado XSIM 2025.1):** 251/251 PASS

### 10.3 Testbench Konvansiyonları

- Testbench dosya adı: `tb_<modül_adı>.sv`
- Clock periyodu: `#1` (mevcut testbench ile uyumlu, 2ns periyot)
- `$display` ve `$error` ile loglama
- `$finish` ile test sonlandırma
- Otomatik pass/fail kontrolü (golden log veya assertion tabanlı)

---

## 11. Copilot'a Özel Talimatlar

### Kod üretirken:

- **Dil**: SystemVerilog (`.sv` uzantısı). Verilog (`.v`) kullanma.
- **Paket**: Her modülde `import riscv_pkg::*;` kullan, gerekirse `axi_pkg::*;` ekle.
- **Reset**: Active-low (`rstn_i`), asenkron. `if (!rstn_i)` ile kontrol et.
- **Saat**: Pozitif kenar tetiklemeli (`posedge clk_i`).
- **AXI**: ARM AMBA AXI4/AXI4-Lite spesifikasyonuna uygun handshake sinyalleri üret.
- **Parametrik tasarım**: Genişlik, derinlik, baud rate gibi değerleri `parameter` ile tanımla.
- **Yorum dili**: Türkçe veya İngilizce — önemli blokların başına açıklama ekle.
- **Sentez uyumlu**: `initial` blokları yalnızca bellek yükleme (`$readmemh`) için kullan. Combinational logic'te tam case coverage sağla.
- **Mevcut koda dokunma**: `rtl/` altındaki mevcut çekirdek dosyalarını değiştirirken mevcut sinyal isimlerini ve port yapılarını koru. Yeni portlar eklenecekse wrapper modülü kullan.

### Dosya oluştururken:

- Yeni dosyaları hedef dizin yapısına uygun konuma koy (Bölüm 7).
- Her dosyanın başına dosya yolu ve kısa açıklama yaz.
- Her modül dosyasının başına `` `timescale 1ns / 1ps `` ekle.

### MATLAB katsayı dosyaları için:

- Hex formatında `.mem` dosyası oluştur.
- Her satır bir katsayı, MSB sola hizalı.
- Dosya başına `// Tap count: N, Format: Q1.15` gibi açıklama ekle.

---

## 12. Hızlı Referans — AXI4-Lite Register Erişim Şablonu

```systemverilog
// Periferal register okuma (firmware tarafında, C pseudo-code):
// volatile uint32_t *UART_BASE = (uint32_t *)0x40000000;
// uint32_t status = UART_BASE[STATUS_OFFSET >> 2];

// Periferal register yazma:
// UART_BASE[TX_DATA_OFFSET >> 2] = 'A';
```

Bu, RISC-V çekirdeğinde bir `SW` (store word) veya `LW` (load word) talimatına karşılık gelir ve AXI master bridge üzerinden periferal register'a erişim sağlar.
