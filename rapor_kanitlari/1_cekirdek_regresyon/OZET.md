# Çekirdek Regresyon Testi — Sonuç Özeti

**Tarih:** 9 Temmuz 2026  
**Araç:** AMD Vivado XSIM 2025.1  
**Testbench:** `tb_rv_all` (tb_rv.sv)  
**Yöntem:** Golden-log karşılaştırma (pipeline WB çıkışı vs beklenen değer)

## Sonuç: ✅ 188/188 PASS

| Alt Test | Açıklama | Test Sayısı | Sonuç |
|----------|----------|-------------|-------|
| BASE | Temel RV32I komut seti (ADD, SUB, AND, OR, BEQ, JAL, LW, SW) | 16 | ✅ PASS |
| BUBBLE_SORT | Algoritma doğrulaması — dallanma, döngü, bellek erişim | 115 | ✅ PASS |
| BOOK | Referans ders kitabı test programı | 20 | ✅ PASS |
| LSU | Load-Store Unit — byte/half/word erişim, işaret uzatma | 37 | ✅ PASS |

## Doğrulama Yöntemi
`rv_scoreboard` modülü, pipeline WB aşamasındaki her commit'i golden log dosyasıyla satır satır karşılaştırır. Register yazma, bellek yazma ve dallanma sonuçları doğrulanır.

## Kanıt Dosyası
- `cekirdek_regresyon_188pass.log` — XSIM konsol çıktısının tam kaydı
