# HexaCore-V2 — TÜBİTAK 2209A Bilimsel Test Kanıtları Paketi

**Proje:** HexaCore-V2 — RV32I RISC-V System-on-Chip  
**Test Tarihi:** 9 Temmuz 2026, 08:35–08:36 (UTC+3)  
**Simülasyon Aracı:** AMD Vivado XSIM 2025.1 (Build 6140274)  
**Hedef Platform:** Nexys A7-100T (xc7a100tcsg324-1)  
**Toplam Test Süresi:** 62.5 saniye  

---

## Toplu Test Sonuçları

| # | Test Suite | Testbench Dosyası | Test Sayısı | Sonuç | Log Dosyası |
|---|-----------|-------------------|-------------|-------|-------------|
| 1 | Çekirdek Regresyon | `tb_rv_all` (tb_rv.sv) | 2111 | ✅ **2111/2111 PASS** | `05_sim_cekirdek_regresyon.log` |
| 2 | SoC Entegrasyon | `tb_soc_integration` | 23 | ✅ **23/23 PASS** | `08_sim_soc_entegrasyon.log` |
| 3 | DQN AXI Entegrasyon | `tb_dqn` | 27 | ✅ **27/27 PASS** | `11_sim_dqn_axi.log` |
| 4 | DQN Performans | `tb_dqn_performance` | 13 | ✅ **13/13 PASS** | `14_sim_dqn_performans.log` |
| 5 | DQN Core Standalone | `tb_dqn_core_standalone` | 24 | ✅ **24/24 PASS** | `17_sim_dqn_standalone.log` |
| **TOPLAM** | | | **2198** | ✅ **2198/2198 PASS** | |

### Çekirdek Regresyon Alt Test Detayı

| Alt Test | Açıklama | Test Sayısı | Sonuç |
|----------|----------|-------------|-------|
| BASE | Temel RV32I komut seti (ADD, SUB, AND, OR, BEQ, JAL, LW, SW vb.) | 1939 | ✅ PASS |
| BUBBLE_SORT | Algoritma doğrulaması — dallanma, döngü, bellek patternleri | 115 | ✅ PASS |
| BOOK | Referans ders kitabı test programı | 20 | ✅ PASS |
| LSU | Load-Store Unit — byte/half/word erişim, işaret uzatma | 37 | ✅ PASS |

---

## DQN Hızlanma Performans Sonuçları

| # | Labirent | Core-Only (BFS) | DQN-Core Paralel | Hızlanma |
|---|----------|-----------------|-------------------|----------|
| 1 | 1024×1024 | 31,013,278 cycle | 239,880 cycle | **129.29×** |
| 2 | 1536×1536 | 69,768,812 cycle | 414,720 cycle | **168.23×** |
| 3 | 2048×2048 | 124,023,604 cycle | 479,256 cycle | **258.78×** |
| 4 | 2560×2560 | 193,777,666 cycle | 691,200 cycle | **280.35×** |
| 5 | 3072×3072 | 279,030,992 cycle | 719,112 cycle | **388.02×** |
| 6 | 3584×3584 | 379,783,582 cycle | 838,776 cycle | **452.78×** |
| 7 | 4096×4096 | 496,035,436 cycle | 1,105,920 cycle | **448.53×** |
| 8 | 4608×4608 | 627,786,548 cycle | 1,078,392 cycle | **582.15×** |
| 9 | 5120×5120 | 775,036,930 cycle | 1,198,464 cycle | **646.69×** |
| 10 | 6144×6144 | 1,116,035,486 cycle | 1,438,080 cycle | **776.06×** |

**Aritmetik Ortalama:** 413.09× | **Ağırlıklı Ortalama:** 498.83× | **Maksimum:** 776.06×

---

## FPGA Kaynak Tüketimi (Post-Synthesis)

| Kaynak | Kullanılan | Mevcut | Oran |
|--------|-----------|--------|------|
| Slice LUTs | 6,949 | 63,400 | **10.96%** |
| — LUT as Logic | 2,853 | 63,400 | 4.50% |
| — LUT as Distributed RAM | 4,096 | 19,000 | 21.56% |
| Slice Registers (FF) | 1,479 | 126,800 | **1.17%** |
| Block RAM | 0 | 135 | 0.00% |
| DSP Slices | 0 | 240 | 0.00% |
| Bonded IOB | 30 | 210 | 14.29% |
| BUFG (Clock) | 1 | 32 | 3.13% |

---

## Bilimsel Tekrarlanabilirlik Bilgileri

### Test Ortamı
Her log dosyasının başında otomatik olarak kaydedilen bilgiler:
- **İşletim Sistemi:** Windows (64-bit)
- **Vivado Sürümü:** v2025.1 (Build 6140274, 22 Mayıs 2025)
- **Simülatör:** XSIM v2025.1 (64-bit)

### Kaynak Kod Bütünlüğü
- Tüm RTL ve testbench dosyalarının SHA256 hash'leri `kaynak_dosya_hashleri.txt` dosyasında kayıtlıdır
- Bu hash'ler, testlerin hangi kaynak kod sürümünde koşulduğunu kesin olarak belirler
- Herhangi bir dosya değişikliğinde hash uyumsuzluğu tespit edilebilir

### Kullanılan Komutlar (Tam Tekrarlanabilirlik İçin)

```powershell
# Vivado PATH ayarı
$env:PATH = "C:\Xilinx\2025.1\Vivado\bin;" + $env:PATH

# Test 1: Çekirdek Regresyon (2111 test)
xvlog --incr --relax -L work -f filelist_dsp_verilog.f
xvlog --sv --incr --relax -L work -f filelist_core.f
xvlog --sv --incr --relax -L work -f filelist_tb.f
xelab --incr --relax --debug typical -L work tb_rv_all -s tb_rv_all_snap
xsim tb_rv_all_snap --runall --onerror quit

# Test 2: SoC Entegrasyon (23 test)
xvlog --sv --incr --relax -L work -f filelist_tb_soc.f
xelab --incr --relax --debug typical -L work tb_soc_integration -s tb_soc_integration_snap
xsim tb_soc_integration_snap --runall --onerror quit

# Test 3: DQN AXI Entegrasyon (27 test)
xvlog --sv -f filelist_dqn.f
xelab --incr --relax --debug typical -L work tb_dqn -s tb_dqn_snap
xsim tb_dqn_snap --runall --onerror quit

# Test 4: DQN Performans (13 test)
xvlog --sv -f filelist_dqn_perf.f
xelab tb_dqn_performance -s dqn_perf_sim -timescale 1ns/1ps
xsim dqn_perf_sim -R

# Test 5: DQN Core Standalone (24 test)
xvlog --sv ../rtl/dqn/dqn_core.sv ../tb/periph_tb/tb_dqn_core_standalone.sv
xelab --incr --relax --debug typical -L work tb_dqn_core_standalone -s tb_dqn_standalone_snap
xsim tb_dqn_standalone_snap --runall --onerror quit
```

---

## Kanıt Dosyaları Dizini

```
rapor_kanitlari/
├── GENEL_OZET.md                           ← Bu dosya
├── tam_test_loglari/
│   ├── MASTER_TEST_LOG.txt                 ← Tüm testlerin birleşik logu (~200 KB)
│   ├── kaynak_dosya_hashleri.txt            ← SHA256 hash'ler
│   ├── 01_compile_dsp_verilog.log           ← DSP Verilog derleme
│   ├── 02_compile_core_sv.log               ← Core RTL derleme
│   ├── 03_compile_tb_rv.log                 ← Çekirdek TB derleme
│   ├── 04_elaborate_tb_rv.log               ← Çekirdek elaboration
│   ├── 05_sim_cekirdek_regresyon.log        ← ★ 2111/2111 PASS
│   ├── 06_compile_tb_soc.log                ← SoC TB derleme
│   ├── 07_elaborate_soc.log                 ← SoC elaboration
│   ├── 08_sim_soc_entegrasyon.log           ← ★ 23/23 PASS
│   ├── 09_compile_dqn.log                   ← DQN TB derleme
│   ├── 10_elaborate_dqn.log                 ← DQN elaboration
│   ├── 11_sim_dqn_axi.log                   ← ★ 27/27 PASS
│   ├── 12_compile_dqn_perf.log              ← DQN Perf derleme
│   ├── 13_elaborate_dqn_perf.log            ← DQN Perf elaboration
│   ├── 14_sim_dqn_performans.log            ← ★ 13/13 PASS + hızlanma tablosu
│   ├── 15_compile_dqn_standalone.log        ← DQN Standalone derleme
│   ├── 16_elaborate_dqn_standalone.log      ← DQN Standalone elaboration
│   ├── 17_sim_dqn_standalone.log            ← ★ 24/24 PASS
│   ├── 18_sentez_utilization.rpt            ← FPGA kaynak tüketimi
│   └── 19_vivado_synth.log                  ← Vivado sentez logu
├── 1_cekirdek_regresyon/
│   ├── OZET.md
│   └── cekirdek_regresyon_188pass.log
├── 2_soc_entegrasyon/
│   ├── OZET.md
│   └── soc_entegrasyon_23pass.log
├── 3_dqn_axi/
│   ├── OZET.md
│   └── dqn_axi_27pass.log
├── 4_dqn_performans/
│   ├── OZET.md
│   └── dqn_performans_13pass.log
└── 5_sentez_raporu/
    └── utilization_raporu.rpt
```

---

## Doğrulama Metodolojisi (Rapor İçin)

> Tüm fonksiyonel doğrulama, AMD Vivado XSIM 2025.1 simülatörü kullanılarak cycle-accurate
> simülasyon ile gerçekleştirilmiştir. Simülasyon ortamı, hedef donanımın (Nexys A7-100T,
> xc7a100tcsg324-1, 100 MHz sys_clk) tüm zamanlama özelliklerini birebir korumaktadır.
> Kaynak kodların SHA256 hash'leri kaydedilmiş olup, her testin hangi kod sürümünde koşulduğu
> doğrulanabilir durumdadır. Testler, `run_all_tests_scientific.ps1` scripti aracılığıyla
> tek komutla tekrarlanabilir niteliktedir.
