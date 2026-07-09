# DQN Performans Testi — Sonuç Özeti

**Tarih:** 9 Temmuz 2026  
**Araç:** AMD Vivado XSIM 2025.1  
**Testbench:** `tb_dqn_performance` (tb_dqn_performance.sv)  
**Yöntem:** Core-Only BFS vs DQN-Core Paralel labirent çözümü karşılaştırması

## Sonuç: ✅ 13/13 PASS

## Performans Tablosu

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

## Özet Metrikler

| Metrik | Değer |
|--------|-------|
| Aritmetik Ortalama Hızlanma | **413.09×** |
| Minimum Hızlanma | 129.29× (1024×1024) |
| Maksimum Hızlanma | **776.06×** (6144×6144) |
| Ağırlıklı Ortalama | **498.83×** |
| Toplam Core-Only Cycle | 4,092,292,334 |
| Toplam DQN-Paralel Cycle | 8,203,800 |
| DQN HW Inference | 33 cycle (boyuttan bağımsız) |

## Karmaşıklık Analizi
- **BFS:** O(N²) — her düğüm ~59 cycle, ~0.45×N² düğüm ziyareti
- **DQN:** O(N) — ~2.5N adım × ~70 cycle/adım
- **Teorik Hızlanma:** ~0.15×N (labirent büyüdükçe doğrusal artış)

## Kanıt Dosyası
- `dqn_performans_13pass.log` — XSIM konsol çıktısının tam kaydı (performans tablosu dahil)
