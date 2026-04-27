# HexaCore-V2

![Status](https://img.shields.io/badge/status-success-green)
![Vivado](https://img.shields.io/badge/Vivado-2025.1-blue)
![FPGA](https://img.shields.io/badge/FPGA-Artix--7-100T-orange)

HexaCore-V2, RISC-V mimarisi ve Deep Q-Learning (DQN) hızlandırıcı içeren tam kapsamlı bir SoC (System-on-Chip) tasarımıdır. Bu proje, üniversite araştırma projeleri için geliştirilmiş olup FPGA üzerinde donanım testleri ve performans analizleri için uygun bir platform sağlar.

## 📋 Özellikler

- **RISC-V 5-stage pipeline mimarisi** (RV32I)
- **Deep Q-Learning (DQN) hızlandırıcı** (4→16→4 neural network)
- **AXI4-Lite veriyolu mimarisi**
- **DSP FIR filtre modülü**
- **UART, I2C, SPI periferik arayüzleri**
- **16KB Instruction Memory, 32KB Data Memory**
- **32 × 32-bit genel amaçlı register**

## 🎯 Hedef Platform

- **FPGA**: Digilent Nexys A7-100T (xc7a100tcsg324-1)
- **Saat Frekansı**: 100 MHz
- **Geliştirme Ortamı**: Xilinx Vivado 2025.1

## 📊 Kaynak Kullanımı

| Kaynak | Kullanılan | Toplam | % |
|--------|-----------|--------|---|
| Slice LUTs | 6,976 | 63,400 | 11.00% |
| Slice Registers | 1,501 | 126,800 | 1.18% |
| Block RAM | 0 | 135 | 0.00% |
| DSPs | 0 | 240 | 0.00% |
| IO Pads | 29 | 210 | 13.81% |

## ⚡ Timing Sonuçları

- **WNS**: +0.046 ns ✅
- **TNS**: 0.000 ns ✅
- **WHS**: +0.072 ns ✅
- **Durum**: Tüm timing kısıtları karşılandı

## 🚀 Hızlı Başlangıç

### Gereksinimler

- Xilinx Vivado 2025.1 veya üzeri
- Digilent Nexys A7-100T FPGA kartı
- USB-JTAG programlama kablosu

### Kurulum

```bash
# Depoyu klonlayın
git clone https://github.com/your-repo/hexacore-v2.git
cd hexacore-v2

# Vivado projesini oluşturun
vivado -mode batch -source vivado/create_project.tcl

# Synthesis ve Implementation
vivado -mode batch -source vivado/run_implementation.tcl

# Bitstream oluşturma
vivado -mode batch -source vivado/generate_bitstream.tcl
```

### FPGA'ya Yükleme

```bash
# Hardware Manager ile
vivado -mode gui
# Open Hardware Manager → Open target → Auto Connect → Program Device
```

## 📁 Proje Yapısı

```
HexaCore-V2/
├── rtl/                    # RTL kaynak kodları
│   ├── top/               # Top-level modüller
│   ├── bus/               # Veriyolu modülleri
│   ├── dqn/               # DQN hızlandırıcı
│   ├── dsp/               # DSP filtre
│   ├── peripherals/       # Periferikler
│   └── hexacore/          # HexaCore CPU
├── tb/                     # Testbench'ler
├── constraints/           # Pin ve timing kısıtları
├── vivado/                # Vivado proje dosyaları
├── PROJE_RAPORU.md         # Detaylı teknik rapor
├── USER_GUIDE.md           # Kullanım rehberi
└── FIX_NOTES.md            # Hata düzeltme notları
```

## 🧪 Test Sonuçları

| Test | Durum |
|------|-------|
| Base Test | ✅ PASS |
| Book Test | ✅ PASS |
| Bubble Sort Test | ✅ PASS |
| LSU Test | ✅ PASS |
| DQN Performance Test | ✅ PASS |
| SoC Integration Test | ✅ PASS |

## 📚 Dokümantasyon

- **[PROJE_RAPORU.md](PROJE_RAPORU.md)** - Detaylı teknik rapor, mimari, test sonuçları ve performans analizi
- **[USER_GUIDE.md](USER_GUIDE.md)** - Vivado kullanım rehberi ve adım adım talimatlar
- **[FIX_NOTES.md](FIX_NOTES.md)** - Karşılaşılan sorunlar ve çözümler

## 🏗️ Mimarisi

### RISC-V Pipeline
- **IF**: Instruction Fetch
- **ID**: Instruction Decode
- **EX**: Execute
- **MEM**: Memory Access
- **WB**: Write Back

### DQN Hızlandırıcı
- **Input Layer**: 4 neurons
- **Hidden Layer**: 16 neurons (ReLU activation)
- **Output Layer**: 4 neurons (Q-values)
- **Format**: Fixed-point Q1.15

### Periferikler
- **UART**: 115200 baud, 8-bit data
- **I2C**: Standart I2C arayüzü
- **SPI**: 4-bit slave select, 1-bit MISO/MOSI
- **GPIO**: 16-bit genel amaçlı I/O

## 🔧 Geliştirme

### Synthesis Stratejisi
- Strategy: Vivado Synthesis Defaults
- Optimization: Explore
- Retiming: Enabled

### Implementation Stratejisi
- Strategy: Performance_ExplorePostRoutePhysOpt
- Placement Directive: Explore
- Routing Directive: AggressiveExplore

## 📄 Lisans

Bu proje akademik araştırma amaçlıdır.

## 👥 Katkıda Bulunma

Katkılarınızı bekliyoruz! Lütfen issue açmadan önce mevcut sorunları kontrol edin.

## 📧 İletişim

Sorularınız için GitHub Issues kullanabilirsiniz.

---

**HexaCore-V2** - FPGA tabanlı RISC-V ve Deep Learning hızlandırıcı platformu
