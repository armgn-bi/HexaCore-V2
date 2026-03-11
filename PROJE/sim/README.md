# Simülasyon Kılavuzu — Vivado XSIM

Bu dizin (`sim/`), Vivado XSIM araçlarını kullanarak RISC-V SoC projesini simüle etmek için gerekli dosyaları içerir.

## Ön Koşullar

1. **Vivado yüklü** olmalı (2025.1 veya üstü önerilir).
2. Vivado `bin` dizini **PATH** ortam değişkeninde olmalı.

### PATH Ayarı (PowerShell)

```powershell
# Vivado yolunuzu kendi kurulumunuza göre düzenleyin:
$env:PATH = "C:\Xilinx\2025.1\Vivado\bin;" + $env:PATH
```

### PATH Ayarı (Bash / WSL)

```bash
export PATH=/opt/Xilinx/2025.1/Vivado/bin:$PATH
```

## Dizin Yapısı

```
sim/
├── Makefile               # GNU Make ile simülasyon (Linux/WSL/Git Bash)
├── run_sim.ps1            # PowerShell ile simülasyon (Windows — önerilen)
├── run_sim.bat            # CMD ile simülasyon (Windows — alternatif)
├── filelist_core.f        # RTL kaynak dosya listesi (SystemVerilog)
├── filelist_dsp_verilog.f # DSP FIR filtre dosya listesi (plain Verilog)
├── filelist_tb.f          # Testbench dosya listesi (çekirdek testleri)
├── filelist_tb_soc.f      # SoC entegrasyon testbench dosya listesi
├── xsim_run.tcl           # XSIM batch Tcl scripti (basit)
├── xsim_run_wdb.tcl       # XSIM batch Tcl scripti (WDB waveform kaydı)
└── README.md              # Bu dosya
```

## Kullanım

### PowerShell (Windows — Önerilen)

```powershell
cd sim

# Tüm akışı çalıştır: derleme + elaboration + simülasyon
.\run_sim.ps1

# Sadece derleme
.\run_sim.ps1 -Target compile

# Sadece elaboration
.\run_sim.ps1 -Target elaborate

# Sadece simülasyon (daha önce derlenmiş olmalı)
.\run_sim.ps1 -Target sim

# SoC entegrasyon testi (AXI + DMEM + DSP)
.\run_sim.ps1 -Target soc_test

# Waveform GUI aç
.\run_sim.ps1 -Target wave

# Derleme + elaboration kontrolü (simülasyon yok)
.\run_sim.ps1 -Target check

# Temizleme
.\run_sim.ps1 -Target clean

# Yardım
.\run_sim.ps1 -Target help
```

### GNU Make (Linux / WSL / Git Bash)

```bash
cd sim

# Tüm akış
make all

# Adım adım
make compile
make elaborate
make sim

# SoC entegrasyon testi (bağımsız akış)
make soc_test

# Waveform
make wave

# VCD kayıtlı simülasyon
make sim_vcd

# Temizleme
make clean
```

## Simülasyon Akışı

```
┌─────────────────────────────────────────────────┐
│  1. xvlog  — Kaynak dosyaları derle             │
│     • filelist_dsp_verilog.f  (plain Verilog)   │
│     • filelist_core.f         (SystemVerilog)    │
│     • filelist_tb.f           (SystemVerilog)    │
├─────────────────────────────────────────────────┤
│  2. xelab  — Elaboration (snapshot oluştur)     │
│     • Top modül: tb_rv_all                      │
│     • Snapshot: tb_rv_all_snap                  │
├─────────────────────────────────────────────────┤
│  3. xsim   — Simülasyonu çalıştır              │
│     • --runall ile sonuna kadar çalışır         │
│     • Sonuçlar logs/ dizinine yazılır           │
└─────────────────────────────────────────────────┘
```

## Loglar

Tüm araç çıktıları `sim/logs/` dizinine kaydedilir:

| Dosya               | İçerik                              |
|---------------------|-------------------------------------|
| `xvlog_dsp.log`     | DSP Verilog derleme çıktısı         |
| `xvlog_core.log`    | Core/Bus/SoC SV derleme çıktısı     |
| `xvlog_tb.log`      | Testbench derleme çıktısı           |
| `xelab.log`         | Elaboration çıktısı                 |
| `xsim.log`          | Simülasyon çıktısı (PASS/FAIL)      |
| `soc_xvlog_dsp.log` | SoC test — DSP Verilog derleme      |
| `soc_xvlog_core.log`| SoC test — Core/Bus SV derleme      |
| `soc_xvlog_tb.log`  | SoC test — TB derleme               |
| `soc_xelab.log`     | SoC test — Elaboration              |
| `soc_xsim.log`      | SoC test — Simülasyon (PASS/FAIL)   |

## Notlar

- Testbench (`tb_rv.sv`), golden log dosyalarına ihtiyaç duyar. Bu dosyalar `tb/` dizininde `*.golden_clean.log.txt` adıyla bulunmalıdır. Script simülasyon öncesinde `tb/` altındaki `*.mem` ve `*.txt` dosyalarını `sim/` dizinine kopyalar.
- Mevcut testbench 4 test çalıştırır: BASE, BUBBLE, BOOK, LSU.
- Her test, golden log dosyasına karşı otomatik PASS/FAIL kontrolü yapar.
- Golden log dosyaları henüz mevcut değilse, ilk çalıştırmada `$fatal` ile hata verecektir. Bu dosyaları oluşturmak için referans simülasyon yapmanız gerekir.

## Yeni Test / Modül Ekleme

1. Yeni RTL dosyasını ilgili `filelist_*.f` dosyasına ekleyin.
2. Yeni testbench'i `filelist_tb.f`'e ekleyin.
3. `TB_TOP` değişkenini yeni top modüle göre güncelleyin (gerekirse).

## VS Code Entegrasyonu

Proje kökünde `.vscode/tasks.json` dosyası bulunmaktadır. VS Code içinden:

- **Ctrl+Shift+B** → Varsayılan build task: "XSIM: Full Flow"
- **Ctrl+Shift+P** → "Tasks: Run Task" → Listeden seçin

Tanımlı task'lar:
| Task                                     | Açıklama                                     |
|------------------------------------------|----------------------------------------------|
| XSIM: Compile                            | Sadece xvlog derleme                         |
| XSIM: Elaborate                          | Sadece xelab elaboration                     |
| XSIM: Simulate                           | Sadece xsim simülasyon                       |
| XSIM: Full Flow                          | compile + elaborate + sim (varsayılan build) |
| XSIM: Check                              | compile + elaborate (sim yok)                |
| XSIM: SoC Integration Test               | SoC entegrasyon testi (AXI+DMEM+DSP)        |
| XSIM: Waveform GUI                       | Vivado waveform viewer aç                    |
| XSIM: Clean                              | Tüm çıktıları temizle                        |

### Windows CMD (Alternatif)

```cmd
cd sim
run_sim.bat              &:: compile + elaborate + sim
run_sim.bat compile      &:: sadece derleme
run_sim.bat soc_test     &:: SoC entegrasyon testi
run_sim.bat check        &:: derleme + elaboration kontrolü
run_sim.bat clean        &:: temizleme
```
