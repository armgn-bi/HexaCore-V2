# HexaCore-V2

> **RV32I RISC-V System-on-Chip** — 5-aşamalı pipeline işlemci + AXI4-Lite bus + 6 periferal

## Özellikler

| Özellik | Değer |
|---------|-------|
| ISA | RV32I (32-bit integer) |
| Pipeline | 5-aşama (IF → ID → EX → MEM → WB) |
| Bus | AXI4-Lite (1 master, 6 slave) |
| Periferaller | UART, SPI, I2C, DSP FIR, DQN Hızlandırıcı |
| Dahili Bellek | 64 KB IMEM + 32 KB DMEM |
| Hedef Saat | 100 MHz |

## Vivado XSIM Test Sonuçları (11 Mart 2026)

| Testbench | Araç | Sonuç |
|-----------|------|-------|
| tb_rv_all (Çekirdek Regresyon) | XSIM 2025.1 | **188/188 PASS** |
| tb_soc_integration (SoC Entegrasyon) | XSIM 2025.1 | **23/23 PASS** |
| tb_dqn (DQN AXI Entegrasyon) | XSIM 2025.1 | **27/27 PASS** |
| tb_dqn_core_standalone (DQN Core) | iverilog | **24/24 PASS** |
| **TOPLAM (XSIM)** | | **238/238 PASS** |

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
```

## Dokümantasyon

- [PROJE_RAPORU.md](PROJE/PROJE_RAPORU.md) — Kapsamlı proje raporu
- [sim/README.md](PROJE/sim/README.md) — Simülasyon kılavuzu
- [project-memory/soc-architecture.md](PROJE/project-memory/soc-architecture.md) — Mimari referans