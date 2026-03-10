# DSP vs CPU Performans Karşılaştırma Raporu

## Özet

HexaCore-V2 RISC-V SoC üzerinde 11-TAP Hamming FIR filtre işleminin, yazılım (CPU-only) ve donanım hızlandırıcı (DSP) ile gerçekleştirilmesi karşılaştırılmıştır.

**Sonuç:** DSP donanım hızlandırıcısı, CPU'ya göre **14.5x – 34.5x** arası hızlandırma sağlamaktadır.

---

## Test Ortamı

| Özellik | Değer |
|---------|-------|
| **SoC** | HexaCore-V2 RISC-V SoC |
| **İşlemci** | RV32I, 5-stage pipeline (IF/ID/EX/MEM/WB) |
| **Clock** | 100 MHz (simülasyon) |
| **ISA** | RV32I Base (MUL/DIV yok) |
| **DSP** | MATLAB HDL Coder 25.2 — Systolic FIR Filter |
| **Bus** | AXI4-Lite Interconnect |
| **DMEM** | 128 KB dahili (simülasyon) |
| **Simülatör** | AMD XSIM (Vivado 2025.2) |

---

## FIR Filtre Özellikleri

| Parametre | Değer |
|-----------|-------|
| **Tap Sayısı** | 11 |
| **Pencere** | Hamming |
| **Giriş Formatı** | sfix16_En15 (Q1.15) |
| **Çıkış Formatı** | sfix33_En31 (Q2.31) |
| **Katsayı Formatı** | sfix16_En16 (Q0.16) |
| **Mimari** | Systolic pipeline, pre-adder optimizasyonu |
| **Çarpma Sayısı** | 6 (simetrik katsayılar sayesinde 11 yerine) |
| **Pipeline Derinliği** | ~11 clock cycle |

**Katsayılar (Q0.16):** `[0, -290, -1098, 2091, 18473, 29232, 18473, 2091, -1098, -290, 0]`

---

## Cycle-Accurate Sonuçlar

| N (Sample) | CPU Cycle | DSP Cycle | Speedup (CPU/DSP) |
|------------|-----------|-----------|-------------------|
| 64 | 111,505 | 7,700 | **14.48x** |
| 128 | 231,761 | 11,156 | **20.77x** |
| 256 | 472,273 | 18,068 | **26.14x** |
| 512 | 953,297 | 31,892 | **29.89x** |
| 1,024 | 1,915,345 | 59,540 | **32.17x** |
| 2,048 | 3,839,443 | 114,838 | **33.43x** |
| 4,096 | 7,687,633 | 225,428 | **34.10x** |
| 8,192 | 15,384,017 | 446,612 | **34.45x** |

---

## Performans Analizi

### CPU-Only (Yazılım FIR)

CPU testi, shift-and-add algoritması ile 16-bit × 16-bit çarpma gerçekleştirmektedir. RV32I ISA'da donanım çarpıcı (MUL instruction) bulunmadığından, her çarpma işlemi **16 iterasyonluk** bir döngü ile yapılır.

**Her output sample için CPU iş yükü:**
- 11 katsayı × (memory load + shift-and-add multiply + accumulate)
- Her multiply: ~16 × 5 = ~80 instruction
- Toplam: ~11 × (~90 instruction) ≈ ~990 instruction/sample
- Pipeline stall'lar ve branch penalty ile: ~1,750 cycle/sample

**Ölçülen cycle/sample (ortalama):**
- N=64: ~1,742 cycle/sample
- N=8192: ~1,878 cycle/sample (cache etkisi yok, lineer artış)

### DSP Hızlandırıcı (Donanım FIR)

DSP testi, AXI4-Lite bus üzerinden input sample gönderip output okumaktadır. Systolic pipeline mimarisi sayesinde, pipeline dolduktan sonra **her clock cycle'da 1 sonuç** üretilir.

**Her output sample için DSP iş yükü:**
- AXI write (DATA_IN): ~3-4 cycle (pipeline stall dahil)
- STATUS polling: 1-2 AXI read cycle (ilk 10 sample hariç)
- AXI read (DATA_OUT): ~3-4 cycle
- Store + loop overhead: ~5-6 cycle
- Toplam: ~15-20 cycle/sample (pipeline dolu iken)
- İlk ~11 sample: pipeline dolma gecikmesi (~440 extra cycle)

**Ölçülen cycle/sample (ortalama):**
- N=64: ~120 cycle/sample (pipeline dolma etkisi yüksek)
- N=8192: ~54.5 cycle/sample (pipeline dolma etkisi ihmal edilebilir)

### Hızlandırma Eğrisi

```
Speedup
  35x ─┤                                    ╭────────────────
  30x ─┤                          ╭─────────╯
  25x ─┤                  ╭───────╯
  20x ─┤          ╭───────╯
  15x ─┤  ╭───────╯
  10x ─┤  │
   5x ─┤  │
   0x ─┼──┴───┬───┬───┬───┬───┬───┬───┬──
       64  128 256 512 1K  2K  4K  8K
                    N (Sample Sayısı)
```

- **N küçükken (64):** Pipeline dolma overhead'i baskın → 14.5x hızlanma
- **N büyüdükçe:** Overhead amortize olur → 34.5x hızlanma (asimptotik)
- **Teorik maksimum:** ~35-40x (CPU ~1,800 cycle/sample vs DSP ~50 cycle/sample)

---

## Neden Bu Kadar Büyük Fark?

### 1. Donanım Paralelliği (Systolic Pipeline)
DSP filtresi, 11-TAP FIR hesaplamasını **tek clock cycle'da** (pipeline dolu iken) gerçekleştirir. 6 adet paralel çarpıcı + toplayıcı ağacı, tüm katsayı çarpmalarını eşzamanlı yapar.

### 2. MUL Instruction Eksikliği
RV32I base ISA'da donanım çarpıcı yoktur. Her 16×16 çarpma, **16 shift+add** döngüsü gerektirir. RV32M uzantısı (MUL/MULH) olsaydı, CPU performansı ~5-8x artar, DSP speedup ~4-7x'e düşerdi.

### 3. AXI Bus Overhead
DSP'nin hız kazancını sınırlayan tek faktör AXI4-Lite bus overhead'idir. Her sample için ~15-20 cycle harcanması, filtrenin gerçek hesaplama hızından (1 cycle/sample) çok daha yavaştır. AXI-Stream (DMA) kullanılsaydı, DSP throughput ~3-5x daha artardı.

### 4. Pipeline Dolma Gecikmesi
İlk ~11 sample boyunca DSP çıkış üretmez (systolic pipeline dolma süresi). Bu, küçük N değerlerinde hızlanma oranını düşürür.

---

## Sonuç ve Öneriler

| Metrik | CPU-Only | DSP-Accelerated | İyileşme |
|--------|----------|-----------------|----------|
| **Cyc/sample (N=8192)** | 1,878 | 54.5 | **34.5x** |
| **Throughput @100MHz** | ~53K sample/s | ~1.83M sample/s | **34.5x** |
| **Latency (N=64)** | 1.12 ms | 77 μs | **14.5x** |

**Öneriler:**
1. **AXI-Stream DMA** eklenirse DSP throughput ~5x daha artabilir (~170x toplam speedup)
2. **RV32M uzantısı** (MUL instruction) eklenirse CPU performansı ~5-8x artar
3. **Çift-port DMEM** ile CPU ve DSP eşzamanlı erişim sağlanabilir

---

*Rapor: HexaCore-V2 DSP Performance Benchmark*  
*Simülasyon: AMD XSIM (Vivado 2025.2)*  
*Test Infrastructure: tb_dsp_perf.sv + gen_dsp_perf_tests.py*
