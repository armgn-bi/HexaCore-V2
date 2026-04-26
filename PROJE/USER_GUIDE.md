# HexaCore-V2 Kullanım Rehberi

Bu rehber, HexaCore-V2 SoC projesini Vivado'da derlemek, test etmek ve FPGA'ya yüklemek için gerekli adımları içerir.

## 📋 İçindekiler

1. [Gereksinimler](#gereksinimler)
2. [Vivado Projesi Oluşturma](#vivado-projesi-oluşturma)
3. [Synthesis](#synthesis)
4. [Implementation](#implementation)
5. [Bitstream Oluşturma](#bitstream-oluşturma)
6. [FPGA'ya Yükleme](#fpgaya-yükleme)
7. [Simülasyon](#simülasyon)
8. [Sorun Giderme](#sorun-giderme)

---

## Gereksinimler

### Yazılım
- **Xilinx Vivado**: 2025.1 veya üzeri
- **Operating System**: Windows 10/11 veya Linux

### Donanım
- **FPGA Kartı**: Digilent Nexys A7-100T (xc7a100tcsg324-1)
- **USB-JTAG**: Programlama kablosu
- **USB-UART**: Seri iletişim için (opsiyonel)

---

## Vivado Projesi Oluşturma

### Otomatik Proje Oluşturma (Önerilen)

Proje, TCL script ile otomatik olarak oluşturulabilir:

```bash
# Windows
vivado -mode batch -source vivado/create_project.tcl

# Linux
vivado -mode batch -source vivado/create_project.tcl
```

### Manuel Proje Oluşturma

#### 1. Vivado'yu Başlatın

```bash
vivado
```

#### 2. Yeni Proje Oluşturun

1. **File → New Project** seçin
2. **Next** ile devam edin
3. Proje bilgilerini girin:
   - **Project name**: `hexacore_v2`
   - **Project location**: Proje dizini
4. **Next** ile devam edin

#### 3. RTL Project Seçin

- **RTL Project** seçin
- **Do not specify sources at this time** işaretleyin
- **Next** ile devam edin

#### 4. Hedef FPGA Seçin

- **Parts**: `xc7a100tcsg324-1`
- **Next** ile devam edin

#### 5. Default Part Seçin

- **Default Part** seçin
- **Finish** ile projeyi oluşturun

#### 6. Kaynak Dosyalarını Ekleyin

**Add Sources** butonuna tıklayın:

**Design Sources:**
```
rtl/top/nexys_a7_top.sv
rtl/top/soc_top.sv
rtl/bus/axi_pkg.sv
rtl/bus/axi_dmem_slave.sv
rtl/dqn/dqn_accelerator.sv
rtl/dqn/dqn_core.sv
rtl/riscv_pipeline.sv
rtl/imem.sv
rtl/dmem.sv
rtl/register_file.sv
```

**Constraints:**
```
constraints/nexys_a7.xdc
```

---

## Synthesis

### Synthesis Ayarları

1. **Settings** → **Synthesis** → **Options**
2. Aşağıdaki ayarları yapın:
   - **Strategy**: `Vivado Synthesis Defaults`
   - **Optimization Directive**: `Explore`
   - **Retiming**: `Enabled`
   - **Shift Register Extraction**: `Enabled`

### Synthesis Çalıştırın

**GUI ile:**
1. **Run Synthesis** butonuna tıklayın
2. Synthesis tamamlanmasını bekleyin (~1 dakika)

**TCL ile:**
```tcl
launch_runs synth_1 -jobs 4
wait_on_run synth_1
```

### Synthesis Sonuçlarını Kontrol Edin

- **Utilization Report**: Kaynak kullanımını kontrol edin
- **Timing Summary**: Timing kısıtlarını kontrol edin
- **DRC Report**: Tasarım kurallarını kontrol edin

**Beklenen Sonuçlar:**
- Slice LUTs: ~6,976 (%11.00)
- Slice Registers: ~1,501 (%1.18%)
- Timing: Tüm kısıtlar karşılanmalı

---

## Implementation

### Implementation Ayarları

1. **Settings** → **Implementation** → **Options**
2. Aşağıdaki ayarları yapın:
   - **Strategy**: `Performance_ExplorePostRoutePhysOpt`
   - **Placement Directive**: `Explore`
   - **Routing Directive**: `AggressiveExplore`
   - **Physical Optimization**: `ExploreWithRemap`

### Implementation Çalıştırın

**GUI ile:**
1. **Run Implementation** butonuna tıklayın
2. Implementation tamamlanmasını bekleyin (~3 dakika)

**TCL ile:**
```tcl
launch_runs impl_1 -jobs 4
wait_on_run impl_1
```

### Implementation Sonuçlarını Kontrol Edin

- **Utilization Report**: Kaynak kullanımını kontrol edin
- **Timing Summary**: Timing kısıtlarını kontrol edin
- **Power Report**: Güç tüketimini kontrol edin
- **DRC Report**: Tasarım kurallarını kontrol edin

**Beklenen Sonuçlar:**
- WNS: +0.046 ns veya pozitif
- TNS: 0.000 ns
- DRC Hataları: 0
- Routing Hataları: 0

---

## Bitstream Oluşturma

### Bitstream Ayarları

1. **Settings** → **Bitstream** → **Configuration**
2. Aşağıdaki ayarları yapın:
   - **Configuration Rate**: `4`
   - **CRC Check**: `Enable`
   - **FPGA Start-Up Clock**: `CCLK`
   - **Compression**: `Enable`

### Bitstream Oluşturun

**GUI ile:**
1. **Generate Bitstream** butonuna tıklayın
2. Bitstream oluşturma tamamlanmasını bekleyin (~30 saniye)

**TCL ile:**
```tcl
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

### Bitstream Dosyası

Bitstream dosyası şu konumda oluşturulur:
```
vivado/hexacore_v2/hexacore_v2.runs/impl_1/nexys_a7_top.bit
```

Dosya boyutu: ~3.8 MB

---

## FPGA'ya Yükleme

### Hardware Manager'ı Başlatın

**GUI ile:**
1. **Open Hardware Manager** butonuna tıklayın
2. **Open target** → **Auto Connect** seçin

**TCL ile:**
```tcl
open_hw_manager
connect_hw_server
open_hw_target
```

### FPGA'ya Bağlanın

1. **Open target** → **Open New Target**
2. **Next** ile devam edin
3. FPGA kartınızı seçin
4. **Finish** ile tamamlayın

### Bitstream'i Yükleyin

**GUI ile:**
1. **Program Device** butonuna tıklayın
2. Bitstream dosyasını seçin:
   ```
   vivado/hexacore_v2/hexacore_v2.runs/impl_1/nexys_a7_top.bit
   ```
3. **Program** ile yükleyin

**TCL ile:**
```tcl
set_property PROGRAM.FILE {vivado/hexacore_v2/hexacore_v2.runs/impl_1/nexys_a7_top.bit} [get_hw_devices xc7a100t_0]
program_hw_devices [get_hw_devices xc7a100t_0]
```

### Yükleme Sonrası Kontrol

Bitstream yüklendikten sonra:
- LED'lerin yanıp sönmediğini kontrol edin
- UART bağlantısı varsa, seri terminali açın
- Switch'leri test edin

---

## Simülasyon

### Simülasyon Ayarları

1. **Settings** → **Simulation** → **Simulation**
2. Aşağıdaki ayarları yapın:
   - **Target Simulator**: `Vivado Simulator`
   - **Simulation top module**: `tb_rv_all`
   - **Simulation run time**: `1000 ns`

### Simülasyon Çalıştırın

**GUI ile:**
1. **Run Simulation** → **Run Behavioral Simulation**
2. Simülasyon tamamlanmasını bekleyin

**TCL ile:**
```bash
xvlog -sv tb/tb_rv_all.sv rtl/*.sv
xelab -debug typical tb_rv_all -s sim
xsim sim -gui
```

### Waveform Analizi

- **Waveform** penceresinde sinyalleri gözlemleyin
- **Add Signals** ile yeni sinyaller ekleyin
- **Zoom** ile zaman ölçeğini ayarlayın

### Test Sonuçları

Beklenen test sonuçları:
- Base Test: ✅ PASS
- Book Test: ✅ PASS
- Bubble Sort Test: ✅ PASS
- LSU Test: ✅ PASS
- DQN Performance Test: ✅ PASS

---

## Sorun Giderme

### Synthesis Hataları

| Hata | Çözüm |
|------|-------|
| `Multiple drivers` | Sinyal bağlantılarını kontrol edin |
| `Unresolved reference` | Tüm modüllerin eklendiğinden emin olun |
| `Syntax error` | SystemVerilog sözdizimini kontrol edin |
| `Unable to infer BRAM` | Memory yapısını kontrol edin (word-based addressing) |

### Timing Hataları

| Hata | Çözüm |
|------|-------|
| `Setup violation` | Clock frekansını düşürün veya pipeline ekleyin |
| `Hold violation` | Timing kısıtlarını ayarlayın |
| `Pulse width violation` | Clock duty cycle'ini kontrol edin |

### Implementation Hataları

| Hata | Çözüm |
|------|-------|
| `UnBuffered IOs` | IO buffer'larını ekleyin (BUFG, IOB) |
| `Placement failed` | Kaynak kullanımını kontrol edin |
| `Routing failed` | Timing kısıtlarını gevşetin |

### FPGA Programlama Hataları

| Hata | Çözüm |
|------|-------|
| `Device not found` | USB bağlantısını kontrol edin |
| `Programming failed` | Bitstream dosyasını kontrol edin |
| `JTAG chain error` | JTAG kablosunu kontrol edin |

---

## TCL Script ile Otomatik Test

Tüm süreci otomatikleştirmek için TCL script kullanabilirsiniz:

```tcl
# Vivado Otomatik Test Script

# Proje ayarları
set project_name "hexacore_v2"
set project_dir "./vivado/hexacore_v2"
set part_name "xc7a100tcsg324-1"

# Proje oluştur
create_project $project_name $project_dir -part $part_name -force

# Design sources ekle
add_files -norecurse {
    rtl/top/nexys_a7_top.sv
    rtl/top/soc_top.sv
    rtl/bus/axi_pkg.sv
    rtl/bus/axi_dmem_slave.sv
    rtl/dqn/dqn_accelerator.sv
    rtl/dqn/dqn_core.sv
    rtl/riscv_pipeline.sv
    rtl/imem.sv
    rtl/dmem.sv
    rtl/register_file.sv
}

# Constraints ekle
add_files -fileset constrs_1 -norecurse constraints/nexys_a7.xdc

# Top modülü ayarla
set_property top nexys_a7_top [current_fileset]

# Synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Implementation
launch_runs impl_1 -jobs 4
wait_on_run impl_1

# Bitstream oluştur
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "Bitstream oluşturuldu: $project_dir/$project_name.runs/impl_1/nexys_a7_top.bit"
```

Script'i çalıştırmak için:

```bash
vivado -mode batch -source scripts/run_vivado.tcl
```

---

## Kaynaklar

- [Vivado Documentation](https://docs.xilinx.com/r/en-US/ug901-vivado-synthesis)
- [SystemVerilog Reference](https://www.accellera.org/downloads/standards/systemverilog)
- [AXI4 Specification](https://developer.arm.com/documentation/ihi0022/latest/)
- [Nexys A7 Reference Manual](https://reference.digilentinc.com/reference/programmable-logic/nexys-a7/start)

---

## İletişim

Sorularınız için GitHub Issues kullanabilirsiniz:
[https://github.com/your-repo/hexacore-v2/issues](https://github.com/your-repo/hexacore-v2/issues)
