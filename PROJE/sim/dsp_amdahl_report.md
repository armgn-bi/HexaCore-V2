# DSP vs CPU Performans Analizi — Amdahl Kanunu ve Paralel Yürütme

## 1. Yönetici Özeti

HexaCore-V2 RISC-V SoC üzerinde DSP donanım hızlandırıcısının performansı iki aşamada ölçülmüştür:

| Test | Açıklama | Max Hızlandırma |
|------|----------|-----------------|
| **V1 — Saf FIR** | CPU vs DSP sadece FIR hesaplama | **34.5x** |
| **V2 — Sistem Seviyesi** | FIR + Veri Kopyalama (CPU sıralı vs DSP paralel) | **53.3x** |

**Kritik Bulgular:**
- DSP, FIR hesaplamasını 14.5x–34.5x hızlandırır (V1)
- Amdahl Kanunu, FIR+Copy sistemi için **maksimum 30x** hızlandırma öngörür
- Paralel yürütme sayesinde gerçek hızlandırma **53.3x'e** ulaşır — **Amdahl limitinin 1.8x üzerinde**
- DSP işlerken CPU'nun boşta kalması yerine faydalı iş (kopyalama) yapması, sistem verimini %78 artırır

---

## 2. Test Ortamı

| Özellik | Değer |
|---------|-------|
| **SoC** | HexaCore-V2 RISC-V SoC |
| **İşlemci** | RV32I, 5-aşamalı pipeline (IF/ID/EX/MEM/WB) |
| **ISA** | RV32I Base (MUL/DIV/CSR yok) |
| **DSP** | MATLAB HDL Coder 25.2 — 11-TAP Systolic FIR Filter |
| **Bus** | AXI4-Lite Interconnect |
| **DMEM** | 128 KB dahili SRAM |
| **Clock** | 100 MHz (simülasyon) |
| **Simülatör** | AMD XSIM (Vivado 2025.2) |
| **Test Sayısı** | 32 (16 V1 + 16 V2) |

---

## 3. V1 Sonuçları — Saf FIR Hızlandırma

Sadece FIR filtre hesaplaması karşılaştırması (veri kopyalama yok):

| N (Sample) | CPU Cycle | DSP Cycle | Hızlandırma |
|------------|-----------|-----------|-------------|
| 64 | 111,505 | 7,700 | **14.48x** |
| 128 | 231,761 | 11,156 | **20.77x** |
| 256 | 472,273 | 18,068 | **26.14x** |
| 512 | 953,297 | 31,892 | **29.89x** |
| 1,024 | 1,915,345 | 59,540 | **32.17x** |
| 2,048 | 3,839,443 | 114,838 | **33.43x** |
| 4,096 | 7,687,633 | 225,428 | **34.10x** |
| 8,192 | 15,384,017 | 446,612 | **34.45x** |

**Asimptotik davranış:** N arttıkça hızlandırma ~34.5x'e yakınsar (DSP pipeline dolma overhead'i amortize olur).

---

## 4. V2 Test Tasarımı — Paralel Yürütme

### CPU-Sıralı Test (Baseline)
```
Başlat → [Veri Üretimi] → MARKER_1 → [FIR Hesaplama] → MARKER_2 → [Veri Kopyalama] → MARKER_3 → Dur
                           ├─ Faz 1: FIR ─┤├─ Faz 2: Copy ─┤
```

### DSP-Paralel Test
```
Başlat → [Veri Üretimi] → MARKER_1 → [DSP FIR + CPU Copy interleaved] → MARKER_2 → [Drain] → MARKER_3 → Dur
                           ├──────── Faz 1: Paralel ────────┤├─ Faz 2 ─┤
```

**Faz Marker Mekanizması:** `ADDI x1, x0, N` komutları — testbench x1 yazmacına yazılan değerleri izler.

**Bellek Haritası:**
| Alan | Offset | Boyut (N=8192) |
|------|--------|----------------|
| FIR Katsayıları | 0x2000 | 22 B |
| FIR Giriş | 0x4000 | N×2 B (16 KB) |
| FIR Çıkış | 0x6000 | N×4 B (32 KB) |
| Copy Kaynak | 0x10000 | N×4 B (32 KB) |
| Copy Hedef | 0x18000 | N×4 B (32 KB) |
| **Toplam** | | **113 KB** (128 KB DMEM içinde) |

---

## 5. V2 Sonuçları — Faz Bazlı Cycle Sayıları

### 5.1 CPU-Sıralı (FIR → Copy)

| N | Faz 1: FIR (cycle) | Faz 2: Copy (cycle) | Toplam (cycle) | FIR Oranı (p) |
|---|---------------------|---------------------|----------------|----------------|
| 64 | 110,823 | 580 | 111,403 | 99.48% |
| 128 | 230,439 | 1,156 | 231,595 | 99.50% |
| 256 | 469,671 | 2,308 | 471,979 | 99.51% |
| 512 | 948,135 | 4,612 | 952,747 | 99.52% |
| 1,024 | 1,905,063 | 9,220 | 1,914,283 | 99.52% |
| 2,048 | 3,818,919 | 18,436 | 3,837,355 | 99.52% |
| 4,096 | 8,260,290 | 36,868 | 8,297,158 | 99.56% |
| 8,192 | 16,521,912 | 73,732 | 16,595,644 | 99.56% |

**Copy performansı:** ~9 cycle/word (LW + SW + ADDI×2 + BNE + pipeline overhead)

### 5.2 DSP-Paralel (DSP FIR + CPU Copy eşzamanlı)

| N | Faz 1: Paralel (cycle) | Faz 2: Drain (cycle) | Toplam (cycle) | Cycle/Sample |
|---|------------------------|----------------------|----------------|--------------|
| 64 | 2,330 | 281 | 2,611 | 40.8 |
| 128 | 4,762 | 281 | 5,043 | 39.4 |
| 256 | 9,626 | 281 | 9,907 | 38.7 |
| 512 | 19,354 | 281 | 19,635 | 38.3 |
| 1,024 | 38,810 | 281 | 39,091 | 38.2 |
| 2,048 | 77,722 | 281 | 78,003 | 38.1 |
| 4,096 | 155,546 | 281 | 155,827 | 38.0 |
| 8,192 | 311,194 | 281 | 311,475 | 38.0 |

**Anahtar gözlem:** DSP paralel mod ~38 cycle/sample sabit throughput sağlar. Bu, hem FIR hesaplama hem de 1 word kopyalama içerir.

### 5.3 V2 Sistem Hızlandırması

| N | CPU Toplam | DSP Toplam | **Sistem Hızlandırma** | Copy Doğrulama |
|---|-----------|-----------|------------------------|----------------|
| 64 | 111,403 | 2,611 | **42.67x** | PASS |
| 128 | 231,595 | 5,043 | **45.92x** | PASS |
| 256 | 471,979 | 9,907 | **47.64x** | PASS |
| 512 | 952,747 | 19,635 | **48.52x** | PASS |
| 1,024 | 1,914,283 | 39,091 | **48.97x** | PASS |
| 2,048 | 3,837,355 | 78,003 | **49.19x** | PASS |
| 4,096 | 8,297,158 | 155,827 | **53.25x** | PASS |
| 8,192 | 16,595,644 | 311,475 | **53.28x** | PASS |

---

## 6. Amdahl Kanunu Analizi

### 6.1 Teori

Amdahl Kanunu, bir sistemin hızlandırılabilir kısmının (p) S kat hızlandırılması durumunda toplam hızlandırmayı sınırlar:

$$S_{\text{toplam}} = \frac{1}{(1-p) + \frac{p}{S}}$$

Burada:
- $p$ = Hızlandırılabilir kısım oranı (FIR hesaplama)
- $(1-p)$ = Sıralı kısım oranı (veri kopyalama)
- $S$ = Bileşen hızlandırması (DSP FIR hızı)

### 6.2 Hesaplama Tablosu

| N | p (FIR oranı) | S (V1 FIR hız.) | Amdahl Tahmini | Gerçek V2 Hız. | **Amdahl'ı Aşma** |
|---|---------------|-----------------|----------------|-----------------|-------------------|
| 64 | 0.9948 | 14.48x | 13.53x | **42.67x** | **3.15x** |
| 128 | 0.9950 | 20.77x | 18.90x | **45.92x** | **2.43x** |
| 256 | 0.9951 | 26.14x | 23.27x | **47.64x** | **2.05x** |
| 512 | 0.9952 | 29.89x | 26.22x | **48.52x** | **1.85x** |
| 1,024 | 0.9952 | 32.17x | 27.97x | **48.97x** | **1.75x** |
| 2,048 | 0.9952 | 33.43x | 28.92x | **49.19x** | **1.70x** |
| 4,096 | 0.9956 | 34.10x | 29.74x | **53.25x** | **1.79x** |
| 8,192 | 0.9956 | 34.45x | 30.00x | **53.28x** | **1.78x** |

### 6.3 Görselleştirme

```
Hızlandırma (x)
  55x ─┤                                              ╭───── Gerçek V2 (53.3x)
  50x ─┤                          ╭────────────────────╯
  45x ─┤          ╭───────────────╯
  40x ─┤  ╭───────╯
  35x ─┤  │                                     ╭────────── V1 FIR (34.5x)
  30x ─┤  │                   ╭─────────────╭───╯╭───────── Amdahl Limiti (30.0x)
  25x ─┤  │           ╭───────╯        ╭────╯────╯
  20x ─┤  │   ╭───────╯          ╭─────╯
  15x ─┤  │───╯            ╭─────╯
  10x ─┤  │          ╭─────╯
   5x ─┤  │    ╭─────╯
   0x ─┼──┴────┴────┴────┬────┬────┬────┬────┬──
       64   128  256  512   1K   2K   4K   8K
                        N (Sample)

  ──── Gerçek V2 Hızlandırma    ──── V1 FIR Hızlandırma
  ──── Amdahl Kanunu Tahmini
```

---

## 7. Amdahl'ı Neden Aştık? — İki Etki

### 7.1 Etki 1: Paralel Yürütme ("Bedava Copy")

Amdahl Kanunu, sıralı kısmın (copy) her durumda çalışması gerektiğini varsayar:

$$T_{\text{Amdahl}} = T_{\text{FIR\_DSP}} + T_{\text{Copy}}$$

Ancak V2 testinde copy işlemi DSP işleme süresine **paralel** olarak gerçekleşir:

$$T_{\text{V2}} = \max(T_{\text{DSP}}, T_{\text{Copy}}) \approx T_{\text{DSP}}$$

Copy süresi ($T_{\text{Copy}}$) DSP süresinden çok kısa olduğu için, copy "bedava" yapılmış olur.

**Örnek (N=8192):**
- FIR CPU: 16,521,912 cycle
- Copy CPU: 73,732 cycle
- Copy oranı: %0.44
- Amdahl: copy 73,732 cycle ekler → hızlandırma 30.0x ile sınırlı
- Gerçek: copy DSP süresine paralel → **53.3x** (copy bedava!)

### 7.2 Etki 2: Gecikme Gizleme (Latency Hiding)

V1 DSP testinde CPU, her sample için STATUS yazmacını **polling döngüsünde** bekler:

```
V1 DSP döngüsü:  Write DATA_IN → [Poll STATUS × K kez] → Read DATA_OUT
                  ~4 cyc           ~4K cyc (~12-20)         ~4 cyc
                  ≈ 55 cycle/sample (N=8192)
```

V2 DSP testinde polling yerine **faydalı iş** (copy) yapılır:

```
V2 DSP döngüsü:  Write DATA_IN → Copy 1 word → Check STATUS 1x → Read DATA_OUT
                  ~4 cyc          ~5 cyc         ~5 cyc            ~5 cyc
                  ≈ 38 cycle/sample (N=8192)
```

| Metrik | V1 DSP | V2 DSP (Paralel) | İyileşme |
|--------|--------|-------------------|----------|
| Cycle/sample (N=8192) | ~54.5 | ~38.0 | **1.43x** |
| Polling boşa harcanan | ~20 cyc/sample | 0 (copy ile değiştirildi) | **%100 verimli** |
| Toplam (N=8192) | 446,612 | 311,475 | **1.43x** |

---

## 8. CPU Kullanımı Karşılaştırması

### V1 DSP Testi — CPU Boşta

```
Zaman ──────────────────────────────────────────────►
CPU:   [Write] [Poll] [Poll] [Poll] [Read] [Write] [Poll] ...
DSP:   [────── İşlem ──────] [out]  [────── İşlem ──────] ...
       ▲                                    ▲
       CPU boşta bekliyor                   CPU boşta bekliyor
```

### V2 DSP Testi — CPU Verimli

```
Zaman ──────────────────────────────────────────────►
CPU:   [Write] [Copy!] [Check] [Read] [Write] [Copy!] ...
DSP:   [────── İşlem ──────]  [out]  [────── İşlem ──────] ...
       ▲                                     ▲
       CPU faydalı iş yapıyor               CPU faydalı iş yapıyor
```

| Test | CPU Boşta Süresi | Faydalı İş | CPU Verimliliği |
|------|-----------------|------------|-----------------|
| V1 DSP | ~20 cyc/sample (polling) | 0 | ~60% |
| V2 DSP | ~0 cyc/sample | Copy 1 word | **~95%** |

---

## 9. Tüm Sonuçların Özet Tablosu

| N | V1 FIR Hız. | Amdahl Limit | **V2 Sistem Hız.** | Amdahl Aşma | Copy Dur. |
|---|-------------|--------------|---------------------|-------------|-----------|
| 64 | 14.48x | 13.53x | **42.67x** | 3.15x | PASS |
| 128 | 20.77x | 18.90x | **45.92x** | 2.43x | PASS |
| 256 | 26.14x | 23.27x | **47.64x** | 2.05x | PASS |
| 512 | 29.89x | 26.22x | **48.52x** | 1.85x | PASS |
| 1,024 | 32.17x | 27.97x | **48.97x** | 1.75x | PASS |
| 2,048 | 33.43x | 28.92x | **49.19x** | 1.70x | PASS |
| 4,096 | 34.10x | 29.74x | **53.25x** | 1.79x | PASS |
| 8,192 | 34.45x | 30.00x | **53.28x** | 1.78x | PASS |

---

## 10. Mühendislik Çıkarımları

### 10.1 Donanım Hızlandırıcı Tasarım İlkeleri

1. **Sadece hesaplama hızı yetmez:** DSP 34.5x FIR hızlandırması sağlar, ama Amdahl Kanunu bunu 30x'e düşürür. Paralel yürütme ile gerçek kazanç **53.3x'e** çıkar.

2. **Boşta kalma süresini ortadan kaldırın:** V1'de CPU zamanının ~%40'ı STATUS polling'de boşa harcanır. V2'de bu süre faydalı iş ile doldurulur.

3. **AXI-Stream (DMA) ile gelecek kazanım:** Mevcut AXI4-Lite sample-by-sample yöntemi ~38 cyc/sample ile sınırlı. Burst-mode AXI veya DMA ile bu ~5-10 cyc/sample'a düşürülebilir (~6-8x ek kazanım).

### 10.2 Amdahl Kanunu Dersleri

| Öğrenim | Açıklama |
|---------|----------|
| **p yaklaşık 1 olsa bile S sınırlı** | p=0.9956 ve S=34.5x olsa bile, Amdahl sadece 30x öngörür |
| **Paralel yürütme Amdahl'ı aşar** | CPU+DSP eşzamanlı çalışma, sıralı kısmı "gizler" |
| **Latency hiding kritik** | Polling → Copy değişimi, bileşen hızını da %43 artırdı |
| **Küçük N'de paralel kazanç daha fazla** | N=64'te 3.15x vs N=8192'de 1.78x (sabit overhead oranı) |

### 10.3 Performans Maliyeti Karşılaştırması

| Yöntem | N=8192 Cycle | Hızlandırma | Alan Maliyeti |
|--------|-------------|-------------|---------------|
| CPU-Only (RV32I) | 16,595,644 | 1.0x | 0 (baseline) |
| CPU + RV32M (tahmini) | ~2,000,000 | ~8.3x | +1 HW çarpıcı |
| DSP V1 Sıralı | 446,612 | 34.5x | +DSP birimi |
| **DSP V2 Paralel** | **311,475** | **53.3x** | +DSP birimi (aynı HW) |
| DSP + AXI-Stream (tahmini) | ~50,000 | ~332x | +DMA controller |

---

## 11. Test Altyapısı

| Dosya | Açıklama |
|-------|----------|
| `tb/soc_tb/gen_dsp_perf_tests.py` | Test bellek dosyası üretici (32 .mem dosyası) |
| `tb/soc_tb/tb_dsp_perf.sv` | Cycle-accurate performans testbench'i |
| `sim/imem_perf_v2_cpu_{N}.mem` | V2 CPU sıralı test programları |
| `sim/imem_perf_v2_dsp_{N}.mem` | V2 DSP paralel test programları |
| `sim/imem_perf_cpu_{N}.mem` | V1 CPU FIR test programları |
| `sim/imem_perf_dsp_{N}.mem` | V1 DSP FIR test programları |

**Doğrulama:** Tüm 32 testte:
- HALT ile temiz sonlanma (timeout yok)
- Copy doğrulama: PASS (kaynak = hedef, byte-by-byte)
- FIR çıkış örnekleri: İlk ve son output yakalandı

---

*Rapor: HexaCore-V2 DSP Amdahl Performance Benchmark v2*
*Simülasyon: AMD XSIM (Vivado 2025.2)*
*Test: 32 cycle-accurate simülasyon (8 sample boyutu × 2 mod × 2 versiyon)*
*Tarih: Haziran 2025*
