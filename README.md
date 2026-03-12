# HexaCore-V2

> **RV32I RISC-V System-on-Chip** — 5-aşamalı pipeline işlemci + AXI4-Lite bus + 6 periferal + DQN donanım hızlandırıcı

## Özellikler

| Özellik | Değer |
|---------|-------|
| ISA | RV32I (32-bit integer) |
| Pipeline | 5-aşama (IF → ID → EX → MEM → WB) |
| Bus | AXI4-Lite (1 master, 6 slave) |
| Periferaller | UART, SPI, I2C, DSP FIR, DQN Hızlandırıcı |
| Dahili Bellek | 64 KB IMEM + 32 KB DMEM |
| Hedef Saat | 100 MHz |
| DQN Hızlanma | **129x – 776x** (labirent çözümünde Core-Only'ye göre) |

## Vivado XSIM Test Sonuçları (13 Mart 2026)

| Testbench | Araç | Sonuç |
|-----------|------|-------|
| tb_rv_all (Çekirdek Regresyon) | XSIM 2025.1 | **188/188 PASS** |
| tb_soc_integration (SoC Entegrasyon) | XSIM 2025.1 | **23/23 PASS** |
| tb_dqn (DQN AXI Entegrasyon) | XSIM 2025.1 | **27/27 PASS** |
| tb_dqn_core_standalone (DQN Core) | iverilog | **24/24 PASS** |
| tb_dqn_performance (DQN Performans) | XSIM 2025.1 | **13/13 PASS** |
| **TOPLAM (XSIM)** | | **251/251 PASS** |

### DQN Performans Testi Sonuçları

Core-Only (BFS) vs DQN-Core Paralel labirent çözümü karşılaştırması:

| Labirent | Core-Only (BFS) | DQN-Core Paralel | Hızlanma |
|----------|-----------------|-------------------|----------|
| 1024x1024 | 31,013,278 cycle | 239,880 cycle | **129.3x** |
| 2048x2048 | 124,023,604 cycle | 479,256 cycle | **258.8x** |
| 4096x4096 | 496,035,436 cycle | 1,105,920 cycle | **448.5x** |
| 6144x6144 | 1,116,035,486 cycle | 1,438,080 cycle | **776.1x** |

- **Ortalama hızlanma: 413x** | Ağırlıklı ortalama: 499x
- DQN HW inference: sabit 33 cycle (boyuttan bağımsız)
- BFS O(N²) vs DQN O(N) — labirent büyüdükçe fark katlanarak artar

## Hızlı Başlangıç

```powershell
# Vivado 2025.1 PATH ayarı
$env:PATH = "C:\Xilinx\2025.1\Vivado\bin;" + $env:PATH

# Simülasyon dizinine geç
cd PROJE/sim

# Çekirdek regresyon testi
xvlog --sv --incr --relax -L work -f filelist_core.f
xvlog --incr --relax -L work -f filelist_dsp_verilog.f
xvlog --sv --incr --relax -L work -f filelist_tb.f
xelab --incr --relax --debug typical -L work tb_rv_all -s tb_rv_all_snap
xsim tb_rv_all_snap --runall --onerror quit

# DQN performans testi
xvlog --sv -f filelist_dqn_perf.f
xelab tb_dqn_performance -s dqn_perf_sim -timescale 1ns/1ps
xsim dqn_perf_sim -R
```

## Dokümantasyon

- [PROJE_RAPORU.md](PROJE/PROJE_RAPORU.md) — Kapsamlı proje raporu
- [sim/README.md](PROJE/sim/README.md) — Simülasyon kılavuzu
- [project-memory/soc-architecture.md](PROJE/project-memory/soc-architecture.md) — Mimari referans