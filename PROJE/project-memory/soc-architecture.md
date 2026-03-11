# HexaCore-V2 SoC Mimarisi ve Bağlantı Şeması

> Son güncelleme: 2026-03-11

---

## 1. Genel Bakış

HexaCore-V2, **RV32I** komut seti mimarisini destekleyen 5-aşamalı pipeline RISC-V işlemci çekirdeği etrafında tasarlanmış bir System-on-Chip (SoC) platformudur. Çekirdek, **AXI4-Lite** bus altyapısı üzerinden 6 periferal birime erişim sağlar.

### Temel Özellikler

| Özellik               | Değer                                    |
|------------------------|------------------------------------------|
| ISA                    | RV32I (32-bit integer)                   |
| Pipeline               | 5-aşama (IF → ID → EX → MEM → WB)      |
| Veri genişliği         | 32-bit                                   |
| Adres genişliği        | 32-bit                                   |
| Bus protokolü          | AXI4-Lite                                |
| Dahili IMEM            | 64 KB (ROM, parametre ile init)          |
| Dahili DMEM            | 32 KB (pipeline içi, tek-cycle erişim)   |
| Harici DMEM            | 32 KB (AXI bus üzeri)                    |
| Periferaller           | UART, SPI, I2C, DSP FIR Filtre, DQN Hızlandırıcı  |
| Sistem saati           | 100 MHz (tasarım hedefi)                 |
| Reset                  | Aktif-düşük, asenkron                    |

---

## 2. SoC Blok Diyagramı

```
                          ┌──────────────────────────────────────────────────────────┐
                          │                       soc_top                            │
                          │                                                          │
    ┌─────────────────────┼──────────────────────────────────┐                       │
    │                     │     riscv_pipeline (u_core)       │                       │
    │                     │                                   │                       │
    │   ┌──────┐  instrF  │  ┌────┐  ┌────┐  ┌────┐  ┌────┐ │                       │
    │   │ IMEM ├─────────►│  │ IF │→ │ ID │→ │ EX │→ │MEM │ │→ ┌────┐              │
    │   │ 64KB │          │  └────┘  └────┘  └────┘  └──┬─┘ │  │ WB │              │
    │   └──────┘          │   ↑ stall  ↑ stall  ↑ stall │   │  └────┘              │
    │                     │   └────────┴────────┴────────┤   │                       │
    │  ┌──────────┐       │            ext_stall_w       │   │                       │
    │  │Dahili    │◄──────┤─────── is_int_dmem ──────────┤   │                       │
    │  │DMEM 32KB │       │                              │   │                       │
    │  └──────────┘       │                              │   │                       │
    └─────────────────────┼──────────────────────────────┘   │                       │
                          │              │ ext_mem_*          │                       │
                          │              ▼ (!is_int_dmem)     │                       │
                          │  ┌──────────────────────┐        │                       │
                          │  │  AXI Master IF       │        │                       │
                          │  │  (u_axi_master)      │        │                       │
                          │  └──────────┬───────────┘        │                       │
                          │             │ AXI4-Lite           │                       │
                          │             ▼                     │                       │
                          │  ┌──────────────────────┐        │                       │
                          │  │  AXI Interconnect    │        │                       │
                          │  │  (u_interconnect)    │        │                       │
                          │  │  1-master, 6-slave   │        │                       │
                          │  └──┬───┬───┬───┬───┬───┬─┘      │                       │
                          │     │   │   │   │   │   │        │                       │
                          │     ▼   ▼   ▼   ▼   ▼   ▼        │                       │
                          │    S0  S1  S2  S3  S4  S5        │                       │
                          │   DMEM UART SPI I2C DSP DQN      │                       │
                          │   32KB                            │                       │
                          │     │   │   │   │   │   │        │                       │
                          └─────┼───┼───┼───┼───┼───┼────────┘
                                │   │   │   │   │   │
                                │   │   │   │   │   └─ (dahili DQN inference)
                                │   │   │   │   └─ (dahili FIR filtre)
                                │   │   │   └──── i2c_sda_io, i2c_scl_io
                                │   │   └──────── spi_sck, spi_mosi, spi_miso, spi_ss[3:0]
                                │   └──────────── uart_tx, uart_rx, uart_irq
                                └──────────────── (harici DMEM — bus erişimli)
```

---

## 3. Pipeline Mimarisi

### 3.1 Aşamalar

```
  ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐
  │   IF   │───►│   ID   │───►│   EX   │───►│  MEM   │───►│   WB   │
  │ Fetch  │    │ Decode │    │Execute │    │ Memory │    │WriteBk │
  └────┬───┘    └────┬───┘    └────┬───┘    └────┬───┘    └────────┘
       │             │             │             │
   IMEM.read     RegFile.read  ALU hesap    DMEM R/W      RegFile.write
   PC hesapla    ImmGen         Branch      veya           Result MUX
                 Hazard det.    Compare     AXI istek
```

| Aşama | İşlev | Modüller |
|-------|-------|----------|
| **IF** (Instruction Fetch) | IMEM'den talimat oku, PC güncelle | `imem` |
| **ID** (Instruction Decode) | Talimat çöz, register oku, immediate üret | `main_control`, `register_file`, `imm_gen`, `hazard_unit` |
| **EX** (Execute) | ALU işlemi, branch hesabı, forwarding | `alu`, `alu_control`, `branch_compare`, `forwarding_unit` |
| **MEM** (Memory) | Dahili DMEM veya AXI bus erişimi | `dmem`, ext_mem_* portlar → AXI |
| **WB** (Write Back) | Sonucu register file'a yaz | Result MUX (ALU / Mem / PC+4) |

### 3.2 Tehlike Çözümleme (Hazard Handling)

| Tehlike Türü | Çözüm | Detay |
|-------------|-------|-------|
| **Data Hazard** (RAW) | Forwarding | EX→EX, MEM→EX yönlendirme (forwarding_unit) |
| **Load-Use Hazard** | 1-cycle stall | IF/ID dondur, ID/EX bubble ekle (hazard_unit) |
| **Control Hazard** | Flush | Branch/jump alındığında IF/ID ve ID/EX flush |
| **WB→ID Bypass** | Combinational bypass | Aynı cycle'da yazılan değer ID'de kullanılabilir |
| **AXI Stall** | Tüm pipeline dondurma | ext_stall_w sinyali ile 5 aşama birden durur |

### 3.3 Adres Yönlendirme (Address Routing)

Pipeline MEM aşamasında hedef adrese göre erişim yönlendirilir:

```
                aluY_M (hedef adres)
                       │
                       ▼
              ┌────────────────┐
              │ Adres Decoder  │
              └───────┬────────┘
                      │
          ┌───────────┴───────────┐
          │                       │
    is_int_dmem=1           is_int_dmem=0
    [0x8000_0000,           Diğer tüm adresler
     0x8000_8000)
          │                       │
          ▼                       ▼
   ┌────────────┐        ┌──────────────┐
   │ Dahili DMEM│        │ ext_mem_*    │
   │ (tek cycle)│        │ → AXI Master │
   └────────────┘        │ (stall ile)  │
                         └──────────────┘
```

| Adres Aralığı | Hedef | Gecikme |
|---------------|-------|---------|
| `0x8000_0000 – 0x8000_7FFF` | Dahili DMEM (pipeline içi) | 1 cycle |
| Diğer tüm adresler | AXI Master IF → Interconnect → Slave | ~3-5 cycle |

#### AXI İstek Mekanizması

```
                     ┌───────────────────────────────────────┐
  is_ext_access ─────►  ext_req_sent_q register             │
  ext_mem_ready_i ───►  (tek cycle pulse üretici)           │
                     └──────────┬────────────────────────────┘
                                │
                    ext_mem_read_o / ext_mem_write_o
                    (sadece ilk cycle aktif)
                                │
                                ▼
                    ┌──────────────────────┐
                    │    AXI Master IF     │
                    │  FSM: IDLE→RD/WR     │
                    │  ready_o=0 → stall   │
                    │  ready_o=1 → devam   │
                    └──────────────────────┘
```

- `ext_req_sent_q`: İstek gönderildiğini takip eden register. İlk cycle'da AXI'ye istek gönderilir, sonra yanıt beklenirken pipeline donmuş kalır.
- `ext_stall_w = is_ext_access && !ext_mem_ready_i`: AXI yanıt gelene kadar tüm pipeline aşamaları dondurulur.

---

## 4. AXI4-Lite Bus Altyapısı

### 4.1 Topoloji

```
  ┌─────────────────┐         ┌─────────────────────────┐
  │ riscv_pipeline   │         │   AXI Master IF         │
  │ (ext_mem_* port) │────────►│   (u_axi_master)        │
  └─────────────────┘         │                         │
                              │  mem_read/write → FSM   │
                              │  addr/wdata → AXI AW/W  │
                              │  AXI R/B → rdata/ready  │
                              └───────────┬─────────────┘
                                          │
                          ┌───────────────┴───────────────┐
                          │     AXI Interconnect          │
                          │     (u_interconnect)          │
                          │                               │
                          │  Adres decoder:               │
                          │  addr & ~MASK == BASE → slave │
                          │  Eşleşme yoksa → DECERR       │
                          │                               │
                          │  wr_active_q / rd_active_q    │
                          │  (slave seçimini kilitler)    │
                          └──┬────┬────┬────┬────┬───────┘
                             │    │    │    │    │
                          S0 ▼ S1 ▼ S2 ▼ S3 ▼ S4 ▼
```

### 4.2 AXI Kanalları

AXI4-Lite protokolü 5 bağımsız kanaldan oluşur:

| Kanal | Yön | Sinyaller | İşlev |
|-------|-----|-----------|-------|
| **AW** (Write Address) | M→S | awaddr, awprot, awvalid/awready | Yazma adresi |
| **W** (Write Data) | M→S | wdata, wstrb, wvalid/wready | Yazma verisi + byte strobe |
| **B** (Write Response) | S→M | bresp, bvalid/bready | Yazma yanıtı (OKAY/SLVERR/DECERR) |
| **AR** (Read Address) | M→S | araddr, arprot, arvalid/arready | Okuma adresi |
| **R** (Read Data) | S→M | rdata, rresp, rvalid/rready | Okuma verisi + yanıt |

### 4.3 AXI Master IF — Durum Makinesi (FSM)

```
                  mem_read=1        mem_write=1
                      │                   │
                      ▼                   ▼
              ┌─────────────┐     ┌─────────────┐
              │   S_READ    │     │   S_WRITE   │
              │             │     │             │
   ┌──────── │ AR valid     │     │ AW+W valid  │ ────────┐
   │         │ wait arready │     │ wait aw+w   │         │
   │         └──────┬───────┘     │   ready     │         │
   │                │             └──────┬──────┘         │
   │         arready=1                   │ aw_fire        │
   │                │                    │ + w_fire       │
   │                ▼                    ▼                │
   │         ┌─────────────┐     ┌─────────────┐         │
   │         │  S_R_WAIT   │     │  S_B_WAIT   │         │
   │         │             │     │             │         │
   │         │ wait rvalid │     │ wait bvalid │         │
   │         └──────┬──────┘     └──────┬──────┘         │
   │                │                    │                │
   │         rvalid=1              bvalid=1               │
   │                │                    │                │
   │                ▼                    ▼                │
   │         ┌──────────────────────────────────┐         │
   └────────►│          S_IDLE                  │◄────────┘
             │                                  │
             │  ready_o = 1, stall kalkar       │
             └──────────────────────────────────┘
```

### 4.4 AXI Interconnect — Adres Decoder

Tek master, N-slave yönlendiricisi. Eşleşme koşulu:

```
slave_hit[i] = (addr & ~SLV_MASK[i]) == SLV_BASE[i]
```

Hiçbir slave eşleşmezse → `DECERR` (Decode Error) yanıtı üretilir.

| Slave | Index | Modül | Eşleşme Kuralı |
|-------|-------|-------|-----------------|
| DMEM | 0 | `axi_dmem_slave` | `(addr & ~0x7FFF) == 0x8001_0000` |
| UART | 1 | `axi_uart` | `(addr & ~0x00FF) == 0x4000_0000` |
| SPI | 2 | `axi_spi` | `(addr & ~0x00FF) == 0x4000_0100` |
| I2C | 3 | `axi_i2c` | `(addr & ~0x00FF) == 0x4000_0200` |
| DSP | 4 | `dsp_filter_wrapper` | `(addr & ~0x0FFF) == 0x4000_1000` |
| DQN | 5 | `dqn_accelerator` | `(addr & ~0x0FFF) == 0x4000_2000` |

---

## 5. Bellek Haritası (Memory Map)

```
  0xFFFF_FFFF ┌─────────────────────┐
              │                     │
              │   (Ayrılmamış)      │  ← AXI erişimde DECERR
              │                     │
  0x8001_8000 ├─────────────────────┤
              │  AXI DMEM (32 KB)   │  ← Slave 0: axi_dmem_slave
  0x8001_0000 ├─────────────────────┤
              │  (Ayrılmamış)       │
  0x8000_8000 ├─────────────────────┤
              │  Dahili DMEM (32KB) │  ← Pipeline içi, tek-cycle
  0x8000_0000 ├─────────────────────┤
              │  IMEM (64 KB)       │  ← Dahili ROM (örtüşen adres)
  0x8000_0000 ├─────────────────────┤
              │                     │
              │   (Ayrılmamış)      │
              │                     │
  0x4000_3000 ├─────────────────────┤
              │  DQN (4 KB)         │  ← Slave 5: dqn_accelerator
  0x4000_2000 ├─────────────────────┤
              │  DSP (4 KB)         │  ← Slave 4: dsp_filter_wrapper
  0x4000_1000 ├─────────────────────┤
              │  (Ayrılmamış)       │
  0x4000_0300 ├─────────────────────┤
              │  I2C (256 B)        │  ← Slave 3: axi_i2c
  0x4000_0200 ├─────────────────────┤
              │  SPI (256 B)        │  ← Slave 2: axi_spi
  0x4000_0100 ├─────────────────────┤
              │  UART (256 B)       │  ← Slave 1: axi_uart
  0x4000_0000 ├─────────────────────┤
              │                     │
              │   (Ayrılmamış)      │
              │                     │
  0x0000_0000 └─────────────────────┘
```

### Özet Tablo

| Bölge | Başlangıç | Bitiş | Boyut | Erişim Yolu | Gecikme |
|-------|-----------|-------|-------|-------------|---------|
| IMEM | `0x8000_0000` | `0x8000_FFFF` | 64 KB | Dahili (IF aşaması) | 0 cycle* |
| Dahili DMEM | `0x8000_0000` | `0x8000_7FFF` | 32 KB | Dahili (MEM aşaması) | 1 cycle |
| AXI DMEM | `0x8001_0000` | `0x8001_7FFF` | 32 KB | AXI Slave 0 | ~3–5 cycle |
| UART | `0x4000_0000` | `0x4000_00FF` | 256 B | AXI Slave 1 | ~3–5 cycle |
| SPI | `0x4000_0100` | `0x4000_01FF` | 256 B | AXI Slave 2 | ~3–5 cycle |
| I2C | `0x4000_0200` | `0x4000_02FF` | 256 B | AXI Slave 3 | ~3–5 cycle |
| DSP | `0x4000_1000` | `0x4000_1FFF` | 4 KB | AXI Slave 4 | ~3–5 cycle |
| DQN | `0x4000_2000` | `0x4000_2FFF` | 4 KB | AXI Slave 5 | ~3–5 cycle |

> \* IMEM kombinasyonel okuma — asenkron ROM.

---

## 6. Periferal Detayları

### 6.1 UART (Universal Asynchronous Receiver/Transmitter)

**Modüller:** `axi_uart.sv` → `uart_tx.sv`, `uart_rx.sv`, `uart_fifo.sv`

**Temel Özellikler:**
- 8N1 formatı (8 data bit, no parity, 1 stop bit)
- 16x oversampling baud rate generator
- TX ve RX FIFO (her biri 16 eleman, 8-bit genişlik)
- Programlanabilir baud rate divisor
- Sticky error bayrakları (frame error, overrun error)
- Interrupt desteği: TX empty ve/veya RX not-empty

**Fiziksel Pinler:**

| Pin | Yön | Açıklama |
|-----|-----|----------|
| `uart_tx_o` | Çıkış | UART seri veri çıkışı |
| `uart_rx_i` | Giriş | UART seri veri girişi |
| `uart_irq_o` | Çıkış | Interrupt çıkışı |

**Register Haritası (Base: `0x4000_0000`):**

| Offset | İsim | R/W | Bit Alanları |
|--------|------|-----|-------------|
| `0x00` | TXDATA | W | `[7:0]` TX verisi → TX FIFO'ya yazılır |
| `0x04` | RXDATA | R | `[7:0]` RX verisi ← RX FIFO'dan okunur |
| `0x08` | STATUS | R | `[0]` tx_full, `[1]` tx_empty, `[2]` rx_full, `[3]` rx_empty, `[4]` frame_err *(sticky)*, `[5]` overrun_err *(sticky)* |
| | | W | Herhangi bir yazma → sticky hataları temizler |
| `0x0C` | CTRL | R/W | `[0]` tx_en, `[1]` rx_en, `[2]` tx_ie *(TX empty IRQ en)*, `[3]` rx_ie *(RX not-empty IRQ en)* |
| `0x10` | BAUD_DIV | R/W | `[15:0]` Baud rate divisor — tick16 period = BAUD_DIV + 1 |

**Baud Rate Hesaplama:**
$$\text{BAUD\_DIV} = \frac{f_{clk}}{16 \times \text{baud\_rate}} - 1$$

Örnek (100 MHz, 115200 baud): $\text{BAUD\_DIV} = \frac{100\text{M}}{16 \times 115200} - 1 \approx 53$

**Interrupt:** `uart_irq = (tx_ie & tx_empty) | (rx_ie & ~rx_empty)`

**Bağlantı Şeması:**

```
                    ┌───────────────────────────────────┐
   AXI4-Lite ──────►│          axi_uart                 │
   (Slave 1)        │                                   │
                    │  ┌─────────────┐   ┌───────────┐ │
                    │  │ axi_lite_   │   │  TX FIFO   │ │     ┌──────────┐
                    │  │ slave bridge│──►│  (16x8)    │─┼────►│ uart_tx  │──► uart_tx_o
                    │  │             │   └───────────┘ │     │  8N1     │
                    │  │  reg R/W    │                  │     └──────────┘
                    │  │  interface  │   ┌───────────┐ │     ┌──────────┐
                    │  │             │◄──│  RX FIFO   │◄┼─────│ uart_rx  │◄── uart_rx_i
                    │  └─────────────┘   │  (16x8)    │ │     │  8N1     │
                    │                    └───────────┘ │     └──────────┘
                    │                                   │
                    │  Baud Rate Gen ────────────────── │──► tick16
                    │  IRQ Logic ─────────────────────  │──► uart_irq_o
                    └───────────────────────────────────┘
```

---

### 6.2 SPI (Serial Peripheral Interface) Master

**Modüller:** `axi_spi.sv` → `spi_master.sv`

**Temel Özellikler:**
- Full-duplex 8-bit transfer
- Mode 0–3 desteği (CPOL/CPHA)
- MSB-first seri iletim
- 4 bağımsız chip select hattı (active-low)
- Programlanabilir SCK clock divider
- 2-FF MISO metastability sync
- Interrupt desteği: rx_valid

**Fiziksel Pinler:**

| Pin | Yön | Açıklama |
|-----|-----|----------|
| `spi_sck_o` | Çıkış | SPI saat sinyali |
| `spi_mosi_o` | Çıkış | Master Out / Slave In |
| `spi_miso_i` | Giriş | Master In / Slave Out |
| `spi_ss_o[3:0]` | Çıkış | Chip select (active-low) |

**Register Haritası (Base: `0x4000_0100`):**

| Offset | İsim | R/W | Bit Alanları |
|--------|------|-----|-------------|
| `0x00` | TXDATA | W | `[7:0]` Gönderilecek byte |
| | | R | `[7:0]` Son yazılan TXDATA |
| `0x04` | RXDATA | R | `[7:0]` Son alınan byte |
| `0x08` | STATUS | R | `[0]` busy, `[1]` rx_valid *(sticky)*, `[2]` ready |
| | | W | Herhangi bir yazma → rx_valid temizler |
| `0x0C` | CTRL | R/W | `[0]` en, `[1]` cpol, `[2]` cpha, `[3]` ie, `[5:4]` cs_sel, `[6]` cs_en |
| `0x10` | CLK_DIV | R/W | `[7:0]` SCK clock divider |
| `0x14` | CMD | W | `[0]` start — 1-cycle transfer pulse |

**SCK Frekans Hesaplama:**
$$f_{SCK} = \frac{f_{clk}}{2 \times (\text{CLK\_DIV} + 1)}$$

Örnek (100 MHz, 1 MHz SCK): $\text{CLK\_DIV} = \frac{100\text{M}}{2 \times 1\text{M}} - 1 = 49$

**SPI Modları:**

| Mode | CPOL | CPHA | SCK Idle | Sample Edge | Shift Edge |
|------|------|------|----------|-------------|------------|
| 0 | 0 | 0 | Low | Rising (leading) | Falling (trailing) |
| 1 | 0 | 1 | Low | Falling (trailing) | Rising (leading) |
| 2 | 1 | 0 | High | Falling (leading) | Rising (trailing) |
| 3 | 1 | 1 | High | Rising (trailing) | Falling (leading) |

**Kullanım Akışı (Yazılımdan):**
1. `CLK_DIV ← istenen SCK hızı`
2. `CTRL ← {cs_en, cs_sel, ie, cpha, cpol, en}`
3. `TXDATA ← gönderilecek byte`
4. `CMD ← 0x01` (start pulse → transfer başlar)
5. `STATUS.busy=0` bekle → `RXDATA` oku

**Bağlantı Şeması:**

```
                    ┌───────────────────────────────────┐
   AXI4-Lite ──────►│          axi_spi                  │
   (Slave 2)        │                                   │
                    │  ┌─────────────┐                  │      ┌────────────┐
                    │  │ axi_lite_   │   ┌───────────┐ │      │            │
                    │  │ slave bridge│──►│spi_master │─┼─────►│ SPI Slave  │
                    │  │             │   │           │ │ SCK   │ Cihaz      │
                    │  │  reg R/W    │   │ CPOL/CPHA │ │ MOSI  │            │
                    │  │  interface  │   │ 8-bit     │◄┼──────│            │
                    │  └─────────────┘   │ shift reg │ │ MISO  │            │
                    │                    └───────────┘ │      │            │
                    │                    CS[3:0] ──────┼─────►│ /CS        │
                    │   IRQ ──────────────────────────  │      └────────────┘
                    └───────────────────────────────────┘
```

---

### 6.3 I2C (Inter-Integrated Circuit) Master

**Modüller:** `axi_i2c.sv` → `i2c_master.sv`

**Temel Özellikler:**
- 7-bit slave adresleme
- 8-bit veri transferi
- Open-drain SDA/SCL (tristate mantığı soc_top'da)
- Komut tabanlı arayüz: START / WRITE / READ_ACK / READ_NACK / STOP
- 4-fazlı SCL clock divider (prescale ile ayarlanır)
- 2-FF metastability sync (SDA/SCL girişleri)
- Sticky ACK error bayrağı
- Interrupt desteği: cmd_ready veya ack_err

**Fiziksel Pinler:**

| Pin | Yön | Açıklama |
|-----|-----|----------|
| `i2c_sda_io` | Bidirectional | I2C veri hattı (open-drain) |
| `i2c_scl_io` | Bidirectional | I2C saat hattı (open-drain) |

**Open-Drain Tristate Mantığı (soc_top içinde):**

```
  i2c_scl_io = scl_oe ? 1'b0 : 1'bz    // OE=1 → drive low, OE=0 → release (pull-up)
  i2c_sda_io = sda_oe ? 1'b0 : 1'bz    // Aynı mantık
  scl_i = i2c_scl_io                     // Readback (multi-master arbitration için)
  sda_i = i2c_sda_io                     // ACK/NACK okuma için
```

```
                     VDD
                      │
                     ┌┤├┐  Pull-up (harici)
                     │   │
    soc_top ─────────┤   ├──── i2c_scl_io ──── I2C Slave SCL
    scl_oe=1 → Low   │   │
    scl_oe=0 → Hi-Z  │   │
                     └───┘
                      │
                     ┌┤├┐  Pull-up (harici)
                     │   │
    soc_top ─────────┤   ├──── i2c_sda_io ──── I2C Slave SDA
    sda_oe=1 → Low   │   │
    sda_oe=0 → Hi-Z  │   │
                     └───┘
```

**Register Haritası (Base: `0x4000_0200`):**

| Offset | İsim | R/W | Bit Alanları |
|--------|------|-----|-------------|
| `0x00` | TXDATA | W | `[7:0]` Gönderilecek byte |
| | | R | `[7:0]` Son yazılan TXDATA |
| `0x04` | RXDATA | R | `[7:0]` Alınan byte |
| `0x08` | STATUS | R | `[0]` busy, `[1]` ack_err *(sticky)*, `[2]` rx_valid, `[3]` cmd_ready, `[4]` arb_lost *(reserved)* |
| | | W | Herhangi bir yazma → sticky hataları temizler |
| `0x0C` | CTRL | R/W | `[0]` en *(modül etkin)*, `[1]` ie *(interrupt enable)* |
| `0x10` | PRESCALE | R/W | `[15:0]` SCL clock prescaler |
| `0x14` | CMD | W | `[2:0]` Komut kodu: `001`=START, `010`=WRITE_BYTE, `011`=READ_ACK, `100`=READ_NACK, `101`=STOP |

**SCL Frekans Hesaplama:**
$$f_{SCL} = \frac{f_{clk}}{4 \times (\text{PRESCALE} + 1)}$$

Örnek (100 MHz, 100 kHz SCL): $\text{PRESCALE} = \frac{100\text{M}}{4 \times 100\text{k}} - 1 = 249$

**I2C Master FSM:**

```
         ┌───────┐   cmd=START   ┌───────────┐
         │ IDLE  │──────────────►│  START     │
         │       │               │ SDA↓ SCL↑  │
         └───┬───┘               └─────┬─────┘
             ▲                         │
             │ cmd=STOP          cmd=WRITE
             │                         │
         ┌───┴───┐               ┌─────▼─────┐
         │ STOP  │◄──────────────│ WRITE_BIT  │
         │SCL↑SDA↑│              │ (8 bit)    │
         └───────┘               └─────┬─────┘
                                       │
                                 ┌─────▼─────┐
                                 │ WRITE_ACK  │
                                 │ Check SDA  │
                                 └─────┬─────┘
                                       │
                              ACK err?  │  cmd=READ
                                       │
                                 ┌─────▼─────┐
                                 │ READ_BIT   │
                                 │ (8 bit)    │
                                 └─────┬─────┘
                                       │
                                 ┌─────▼─────┐
                                 │ READ_SEND  │
                                 │ ACK/NACK   │
                                 └───────────┘
```

**Kullanım Akışı (Yazılımdan):**
1. `PRESCALE ← istenen SCL hızı`
2. `CTRL ← 0x01` (enable)
3. `CMD ← 0x01` (START)  →  `STATUS.busy=1`, cmd_ready bekle
4. `TXDATA ← slave_addr<<1` → `CMD ← 0x02` (WRITE) → ACK kontrol
5. `TXDATA ← data_byte` → `CMD ← 0x02` (WRITE) → ACK kontrol
6. `CMD ← 0x05` (STOP)

---

### 6.4 DSP FIR Filtre

**Modüller:** `dsp_filter_wrapper.sv` → `dsphdl_FIRFilter.v` (MATLAB HDL Coder çıktısı)

**Temel Özellikler:**
- Systolic FIR filtre mimarisi
- MATLAB HDL Coder tarafından otomatik üretilmiş Verilog
- 16-bit signed giriş (sfix16_En15, Q1.15 sabit nokta)
- 33-bit signed çıkış (sfix33_En31)
- AXI4-Lite register arayüzü ile kontrol
- Soft reset ve enable kontrolü

**Register Haritası (Base: `0x4000_1000`):**

| Offset | İsim | R/W | Bit Alanları |
|--------|------|-----|-------------|
| `0x00` | CTRL | R/W | `[0]` enable (enb), `[1]` soft_reset *(1-cycle pulse)*, `[2]` start *(1-cycle pulse)* |
| `0x04` | STATUS | R | `[0]` busy, `[1]` out_valid *(çıkış hazır)* |
| `0x08` | DATA_IN | W | `[15:0]` dataIn — yazma anında validIn pulse üretir |
| `0x0C` | DATA_OUT_L | R | `[31:0]` dataOut alt 32 bit |
| `0x10` | DATA_OUT_H | R | `[0]` dataOut[32] (MSB) |

**Veri Akışı:**

```
    CPU (SW) ────► CTRL.enable=1 ────► Filtre aktif
         │
         ├──────► DATA_IN yazma  ────► validIn pulse ────► FIR hesaplama
         │                                                       │
         │                                                 validOut=1
         │                                                       │
         └──────◄ STATUS.out_valid ◄──── DATA_OUT_L/H ◄─────────┘
```

**Bağlantı Şeması:**

```
                    ┌────────────────────────────────────────┐
   AXI4-Lite ──────►│       dsp_filter_wrapper               │
   (Slave 4)        │                                        │
                    │  ┌──────────────┐   ┌───────────────┐ │
                    │  │ axi_lite_    │   │ dsphdl_       │ │
                    │  │ slave bridge │──►│ FIRFilter     │ │
                    │  │              │   │               │ │
                    │  │  CTRL/STATUS │   │ Systolic FIR  │ │
                    │  │  DATA_IN/OUT │   │ sfix16 → s33  │ │
                    │  └──────────────┘   └───────────────┘ │
                    └────────────────────────────────────────┘
```

---

### 6.5 DQN Inference Hızlandırıcı

**Modüller:** `dqn_accelerator.sv` → `dqn_core.sv`

**Temel Özellikler:**
- Deep Q-Network (DQN) inference donanım hızlandırıcısı
- Ağ mimarisi: 4→16→4 (2 Dense Layer, 16 gizli nöron)
- Q1.15 sabit nokta aritmetiği (sfix16_En15, DSP FIR ile aynı)
- LeakyReLU aktivasyon (alpha = 0.01)
- 4 paralel kombinasyonel MAC birimi
- ~33 clock cycle inference süresi (~330 ns @100 MHz)
- 148 ağırlık register (AXI üzerinden yazılım tarafından yüklenir)
- Sadece inference — eğitim yazılımda yapılır
- Argmax donanımı ile en iyi aksiyon doğrudan çıkışta

**Register Haritası (Base: `0x4000_2000`):**

| Offset | İsim | R/W | Bit Alanları |
|--------|------|-----|-------------|
| `0x00` | CTRL | R/W | `[0]` enable, `[1]` start *(self-clearing pulse)*, `[2]` soft_reset *(self-clearing)*, `[3]` wt_load_mode |
| `0x04` | STATUS | R | `[0]` busy, `[1]` done *(sticky)*, `[2]` wt_loaded, `[5:4]` argmax |
| `0x08` | STATE_0 | R/W | `[15:0]` Giriş state[0] Q1.15 |
| `0x0C` | STATE_1 | R/W | `[15:0]` Giriş state[1] Q1.15 |
| `0x10` | STATE_2 | R/W | `[15:0]` Giriş state[2] Q1.15 |
| `0x14` | STATE_3 | R/W | `[15:0]` Giriş state[3] Q1.15 |
| `0x18` | QVAL_0 | R | `[15:0]` Q-value[0] Q1.15 |
| `0x1C` | QVAL_1 | R | `[15:0]` Q-value[1] Q1.15 |
| `0x20` | QVAL_2 | R | `[15:0]` Q-value[2] Q1.15 |
| `0x24` | QVAL_3 | R | `[15:0]` Q-value[3] Q1.15 |
| `0x28` | QVAL_MAX | R | `[15:0]` Max Q-value Q1.15 |
| `0x2C` | WT_ADDR | R/W | `[7:0]` Ağırlık adresi (0–147), auto-increment |
| `0x30` | WT_DATA | R/W | `[15:0]` Ağırlık/bias değeri Q1.15 |
| `0x34` | CYCLE_CNT | R | `[15:0]` Inference süresi (clock cycle) |
| `0x38` | VERSION | R | `0x44514E01` ("DQN" + v1) |

**Ağırlık Bellek Layout (148 adres):**

| Adres Aralığı | İçerik | Boyut | Düzen |
|----------------|--------|-------|-------|
| 0–63 | FC1 weights | 64 | `[input_idx×16 + output_idx]` |
| 64–79 | FC1 biases | 16 | `[neuron_idx]` |
| 80–143 | FC2 weights | 64 | `[(addr-80)/4][((addr-80)%4)]` |
| 144–147 | FC2 biases | 4 | `[neuron_idx]` |

**Inference Datapath:**

```
  State[0..3] ────► 4× MAC (FC1) ────► LeakyReLU ────► Hidden[0..15]
                      (Q1.15×Q1.15)       α=0.01          │
                                                           │
                                                     4× MAC (FC2)
                                                      + FC2 bias
                                                           │
                                                    Q-values[0..3]
                                                           │
                                                      Argmax/Q_max
```

**Kullanım Akışı (Yazılımdan):**
1. `CTRL ← 0x09` (enable + wt_load_mode)
2. `WT_ADDR ← 0` → 148 kez `WT_DATA` yaz (auto-increment)
3. `CTRL ← 0x01` (enable, wt_load_mode=0)
4. `STATE_0..3 ← ortam gözlem değerleri (Q1.15)`
5. `CTRL ← 0x03` (enable + start pulse)
6. STATUS.done=1 bekle (polling)
7. STATUS.argmax → en iyi aksiyon, QVAL_0..3 → Q-değerleri

**Bağlantı Şeması:**

```
                    ┌────────────────────────────────────────┐
   AXI4-Lite ──────►│       dqn_accelerator                  │
   (Slave 5)        │                                        │
                    │  ┌──────────────┐   ┌───────────────┐ │
                    │  │ axi_lite_    │   │   dqn_core    │ │
                    │  │ slave bridge │──►│               │ │
                    │  │              │   │ FSM + 4×MAC   │ │
                    │  │  Reg R/W     │   │ LeakyReLU     │ │
                    │  │  148 WT regs │   │ Argmax        │ │
                    │  └──────────────┘   └───────────────┘ │
                    └────────────────────────────────────────┘
```

---

### 7.1 soc_top Port Listesi

| Grup | Port | Yön | Genişlik | Açıklama |
|------|------|-----|----------|----------|
| **Sistem** | `clk_i` | in | 1 | Sistem saati (100 MHz) |
| | `rstn_i` | in | 1 | Reset (aktif-düşük) |
| **Debug** | `dbg_addr_i` | in | 32 | Debug okuma adresi |
| | `dbg_data_o` | out | 32 | Debug okuma verisi |
| **Scoreboard** | `update_o` | out | 1 | WB valid (retire sinyali) |
| | `pc_o` | out | 32 | Retire edilen PC |
| | `instr_o` | out | 32 | Retire edilen talimat |
| | `reg_addr_o` | out | 5 | Yazılan register adresi |
| | `reg_data_o` | out | 32 | Yazılan register verisi |
| | `mem_addr_o` | out | 32 | Bellek erişim adresi |
| | `mem_data_o` | out | 32 | Bellek verisi |
| | `mem_wrt_o` | out | 1 | Bellek yazma sinyali |
| | `mem_read_o` | out | 1 | Bellek okuma sinyali |
| **UART** | `uart_tx_o` | out | 1 | UART TX |
| | `uart_rx_i` | in | 1 | UART RX |
| | `uart_irq_o` | out | 1 | UART interrupt |
| **SPI** | `spi_sck_o` | out | 1 | SPI clock |
| | `spi_mosi_o` | out | 1 | SPI MOSI |
| | `spi_miso_i` | in | 1 | SPI MISO |
| | `spi_ss_o` | out | 4 | SPI chip select |
| **I2C** | `i2c_sda_io` | inout | 1 | I2C data (open-drain) |
| | `i2c_scl_io` | inout | 1 | I2C clock (open-drain) |
| **DSP Stream** | `dsp_s_tdata_i` | in | 32 | AXI-Stream giriş (reserved) |
| | `dsp_s_tvalid_i` | in | 1 | (reserved) |
| | `dsp_s_tready_o` | out | 1 | (reserved, =0) |
| | `dsp_s_tlast_i` | in | 1 | (reserved) |
| | `dsp_m_tdata_o` | out | 32 | AXI-Stream çıkış (reserved) |
| | `dsp_m_tvalid_o` | out | 1 | (reserved, =0) |
| | `dsp_m_tready_i` | in | 1 | (reserved) |
| | `dsp_m_tlast_o` | out | 1 | (reserved, =0) |

### 7.2 Modül Hiyerarşisi

```
soc_top
├── riscv_pipeline (u_core)
│   ├── imem (u_imem)                    — 64 KB Instruction Memory
│   ├── main_control (u_ctrl)            — Talimat decoder
│   ├── register_file (u_rf)             — 32x32-bit register dosyası
│   ├── imm_gen (u_imm)                  — Immediate üreteci
│   ├── hazard_unit (u_hazard)           — Load-use stall üreteci
│   ├── alu_control (u_aluctrl)          — ALU işlem seçici
│   ├── alu (u_alu)                      — 32-bit ALU
│   ├── branch_compare (u_brcmp)         — Branch koşul değerlendiricisi
│   ├── forwarding_unit (u_fwd)          — Data forwarding kontrolü
│   └── dmem (u_dmem)                    — 32 KB dahili Data Memory
│
├── axi_master_if (u_axi_master)         — Pipeline → AXI4-Lite bridge
│
├── axi_interconnect (u_interconnect)    — 1-master, 6-slave yönlendirici
│
├── axi_dmem_slave (u_axi_dmem)          — Slave 0: AXI DMEM (32 KB)
│   └── dmem (u_dmem)                    — İkinci DMEM instance
│
├── dsp_filter_wrapper (u_dsp_filter)    — Slave 4: DSP FIR Filtre
│   ├── axi_lite_slave (u_axi_slv)      — Generic AXI bridge
│   └── dsphdl_FIRFilter (u_fir)        — MATLAB HDL Coder FIR
│       └── Filter → subFilter → FilterTap... (systolic)
│
├── axi_uart (u_axi_uart)               — Slave 1: UART
│   ├── axi_lite_slave (u_axi_slv)      — Generic AXI bridge
│   ├── uart_fifo (u_tx_fifo)           — TX FIFO (16x8)
│   ├── uart_fifo (u_rx_fifo)           — RX FIFO (16x8)
│   ├── uart_tx (u_tx)                  — UART Transmitter
│   └── uart_rx (u_rx)                  — UART Receiver
│
├── axi_spi (u_axi_spi)                 — Slave 2: SPI Master
│   ├── axi_lite_slave (u_axi_slv)      — Generic AXI bridge
│   └── spi_master (u_spi_core)         — SPI Master Controller
│
└── axi_i2c (u_axi_i2c)                 — Slave 3: I2C Master
    ├── axi_lite_slave (u_axi_slv)      — Generic AXI bridge
    └── i2c_master (u_i2c_core)         — I2C Master Controller

├── dqn_accelerator (u_dqn_accel)       — Slave 5: DQN Inference
    ├── axi_lite_slave (u_axi_slv)      — Generic AXI bridge
    └── dqn_core (u_dqn_core)           — DQN Inference Engine (4→16→4)
```

---

## 8. Sinyal Akış Diyagramları

### 8.1 Store Word (SW) — Dahili DMEM

```
Talimat: SW rs2, offset(rs1)    Hedef: 0x8000_0100 (dahili aralık)

Cycle 1 [IF]  : IMEM[PC] → instrF = SW encoding
Cycle 2 [ID]  : rs1, rs2 oku, immediate üret
Cycle 3 [EX]  : aluY_E = rs1 + offset = 0x8000_0100
Cycle 4 [MEM] : is_int_dmem=1 → DMEM.write(0x8000_0100, rs2)    ← tek cycle
Cycle 5 [WB]  : (yazma yok, SW register'a yazmaz)
```

### 8.2 Load Word (LW) — AXI Bus

```
Talimat: LW rd, offset(rs1)    Hedef: 0x4000_0008 (UART STATUS)

Cycle 1 [IF]  : IMEM[PC] → instrF = LW encoding
Cycle 2 [ID]  : rs1 oku, immediate üret
Cycle 3 [EX]  : aluY_E = rs1 + offset = 0x4000_0008
Cycle 4 [MEM] : is_int_dmem=0 → ext_mem_read_o=1, ext_stall_w=1
                  Pipeline DONDURULDU
Cycle 5 [MEM] : AXI Master IF → AR valid → Interconnect → UART slave
         ...  : ext_req_sent_q=1, read/write pulse sönük
Cycle 6 [MEM] : UART → R channel valid, rdata = STATUS değeri
                  ext_mem_ready_i=1 → ext_stall_w=0
                  Pipeline DEVAM
Cycle 7 [WB]  : readDataW = UART STATUS → rd'ye yazılır
```

### 8.3 AXI Write Transaction Akışı

```
  Pipeline          AXI Master IF       Interconnect        Slave (örn. SPI)
     │                    │                   │                    │
     │ ext_mem_write=1    │                   │                    │
     │ addr=0x4000_010C   │                   │                    │
     │ wdata=0x41         │                   │                    │
     │───────────────────►│                   │                    │
     │                    │ AW: addr=0x010C   │                    │
     │                    │ W:  data=0x41     │                    │
     │  ready=0 (stall)   │──────────────────►│                    │
     │◄───────────────────│                   │ aw/w → Slave 2     │
     │                    │                   │───────────────────►│
     │                    │                   │                    │ Register yazma
     │                    │                   │   B: OKAY          │
     │                    │                   │◄───────────────────│
     │                    │   B: OKAY         │                    │
     │  ready=1           │◄──────────────────│                    │
     │◄───────────────────│                   │                    │
     │  (stall kalkar)    │                   │                    │
```

---

## 9. RTL Dosya Yapısı

```
rtl/
├── riscv_pkg.sv           — RISC-V sabitler ve typedef'ler (XLEN=32, vb.)
├── alu.sv                 — 32-bit ALU (ADD,SUB,AND,OR,XOR,SLT,SLL,SRL,SRA)
├── alu_control.sv         — ALU işlem kodu üreteci
├── branch_compare.sv      — Branch koşul değerlendiricisi (BEQ,BNE,BLT,BGE,BLTU,BGEU)
├── dmem.sv                — Parametrik Data Memory (byte/half/word, signed/unsigned)
├── forwarding_unit.sv     — EX→EX, MEM→EX data forwarding
├── hazard_unit.sv         — Load-use hazard detection (1-cycle stall)
├── imem.sv                — Instruction Memory (asenkron okuma)
├── imm_gen.sv             — Immediate üreteci (I/S/B/U/J formatları)
├── main_control.sv        — Ana kontrol birimi (opcode → kontrol sinyalleri)
├── register_file.sv       — 32x32-bit register dosyası (x0=0, sync write, async read)
├── riscv_pipeline.sv      — 5-aşamalı pipeline üst modül
│
├── bus/
│   ├── axi_pkg.sv         — AXI parametreler, adres haritası, struct typedef'ler
│   ├── axi_master_if.sv   — Pipeline → AXI4-Lite master bridge (FSM)
│   ├── axi_interconnect.sv— 1-master N-slave adres yönlendirici
│   ├── axi_dmem_slave.sv  — AXI4-Lite → DMEM wrapper (FSM)
│   └── axi_lite_slave.sv  — Generic AXI4-Lite → register bridge
│
├── uart/
│   ├── axi_uart.sv        — AXI4-Lite UART periferal wrapper
│   ├── uart_tx.sv         — UART transmitter (8N1, 16x oversampling)
│   ├── uart_rx.sv         — UART receiver (8N1, 16x oversampling, 2-FF sync)
│   └── uart_fifo.sv       — Parametrik senkron FIFO
│
├── spi/
│   ├── axi_spi.sv         — AXI4-Lite SPI periferal wrapper
│   └── spi_master.sv      — SPI master controller (Mode 0–3, multi-slave)
│
├── i2c/
│   ├── axi_i2c.sv         — AXI4-Lite I2C periferal wrapper
│   └── i2c_master.sv      — I2C master controller (7-bit addr, open-drain)
│
├── dsp/
│   ├── dsp_filter_wrapper.sv — AXI4-Lite DSP filtre wrapper
│   ├── dsphdl_FIRFilter.v    — MATLAB HDL Coder FIR filtre üst modül
│   ├── Filter.v              — Filtre çekirdeği
│   ├── FilterCoef.v          — Filtre katsayıları ROM
│   ├── FilterTapSystolicPreAddWvlIn.v  — Systolic tap (pre-add)
│   ├── FilterTapSystolicWvldInC0.v     — Systolic tap (input)
│   └── subFilter.v           — Alt filtre birimi
│
├── dqn/
│   ├── dqn_core.sv            — DQN inference motoru (FSM + MAC + LeakyReLU)
│   └── dqn_accelerator.sv    — AXI4-Lite DQN periferal wrapper
│
└── top/
    └── soc_top.sv          — SoC üst modül (tüm bağlantılar)
```

---

## 10. Test Altyapısı Özeti

| Test | Dosya | Kapsam | Sonuç |
|------|-------|--------|-------|
| Core Regression (BASE) | `tb/tb_rv.sv` + `imem_base.mem` | 1939 talimat (ALU, branch, jump, immediate) | 1939/1939 PASS |
| Core Regression (BUBBLE) | `tb/tb_rv.sv` + `imem_bubble.mem` | 115 adım (bubble sort) | 115/115 PASS |
| Core Regression (BOOK) | `tb/tb_rv.sv` + `imem_book.mem` | 20 adım (ders kitabı testleri) | 20/20 PASS |
| Core Regression (LSU) | `tb/tb_rv.sv` + `imem_lsu.mem` | 37 adım (load/store byte/half/word) | 37/37 PASS |
| SoC Integration (AXI direct) | `tb/soc_tb/tb_soc_integration.sv` | 40 test (DMEM+DSP+UART+SPI+I2C) | 40/40 PASS |
| **Full SoC (Pipeline→AXI→Periph)** | `tb/soc_tb/tb_soc_full.sv` | 9 test (tüm periferaller uçtan uca) | **9/9 PASS** |
| DQN Core Standalone | `tb/periph_tb/tb_dqn_core_standalone.sv` | 24 test (inference, LeakyReLU, argmax, bias, reset) | **24/24 PASS** |
| **Toplam** | | | **2184/2184 PASS** |

---

## 11. Yazılım Geliştirme Kılavuzu (Hızlı Başlangıç)

### Periferal Adresleri (C Header Formatı)

```c
// ── Bellek bölgeleri ──────────────────────────
#define DMEM_INT_BASE   0x80000000   // Dahili DMEM (32 KB)
#define DMEM_AXI_BASE   0x80010000   // AXI DMEM (32 KB)

// ── UART ──────────────────────────────────────
#define UART_BASE       0x40000000
#define UART_TXDATA     (UART_BASE + 0x00)
#define UART_RXDATA     (UART_BASE + 0x04)
#define UART_STATUS     (UART_BASE + 0x08)
#define UART_CTRL       (UART_BASE + 0x0C)
#define UART_BAUD_DIV   (UART_BASE + 0x10)

// ── SPI ───────────────────────────────────────
#define SPI_BASE        0x40000100
#define SPI_TXDATA      (SPI_BASE + 0x00)
#define SPI_RXDATA      (SPI_BASE + 0x04)
#define SPI_STATUS      (SPI_BASE + 0x08)
#define SPI_CTRL        (SPI_BASE + 0x0C)
#define SPI_CLK_DIV     (SPI_BASE + 0x10)
#define SPI_CMD         (SPI_BASE + 0x14)

// ── I2C ───────────────────────────────────────
#define I2C_BASE        0x40000200
#define I2C_TXDATA      (I2C_BASE + 0x00)
#define I2C_RXDATA      (I2C_BASE + 0x04)
#define I2C_STATUS      (I2C_BASE + 0x08)
#define I2C_CTRL        (I2C_BASE + 0x0C)
#define I2C_PRESCALE    (I2C_BASE + 0x10)
#define I2C_CMD         (I2C_BASE + 0x14)

// ── DSP FIR Filtre ────────────────────────────
#define DSP_BASE        0x40001000
#define DSP_CTRL        (DSP_BASE + 0x00)
#define DSP_STATUS      (DSP_BASE + 0x04)
#define DSP_DATA_IN     (DSP_BASE + 0x08)
#define DSP_DATA_OUT_L  (DSP_BASE + 0x0C)
#define DSP_DATA_OUT_H  (DSP_BASE + 0x10)

// ── DQN Inference Hızlandırıcı ──────────────
#define DQN_BASE        0x40002000
#define DQN_CTRL        (DQN_BASE + 0x00)
#define DQN_STATUS      (DQN_BASE + 0x04)
#define DQN_STATE_0     (DQN_BASE + 0x08)
#define DQN_STATE_1     (DQN_BASE + 0x0C)
#define DQN_STATE_2     (DQN_BASE + 0x10)
#define DQN_STATE_3     (DQN_BASE + 0x14)
#define DQN_QVAL_0      (DQN_BASE + 0x18)
#define DQN_QVAL_1      (DQN_BASE + 0x1C)
#define DQN_QVAL_2      (DQN_BASE + 0x20)
#define DQN_QVAL_3      (DQN_BASE + 0x24)
#define DQN_QVAL_MAX    (DQN_BASE + 0x28)
#define DQN_WT_ADDR     (DQN_BASE + 0x2C)
#define DQN_WT_DATA     (DQN_BASE + 0x30)
#define DQN_CYCLE_CNT   (DQN_BASE + 0x34)
#define DQN_VERSION     (DQN_BASE + 0x38)
```

### Basit UART Yazma Örneği (RISC-V Assembly)

```asm
# UART'a 'A' (0x41) karakteri gönder
# UART_BASE = 0x4000_0000

    lui   t0, 0x40000       # t0 = 0x40000000 (UART base)

    # TX enable
    li    t1, 0x01           # tx_en = 1
    sw    t1, 0x0C(t0)      # CTRL ← 0x01

    # Baud rate = 115200 @ 100MHz
    li    t1, 53             # BAUD_DIV = 53
    sw    t1, 0x10(t0)      # BAUD_DIV ← 53

wait_tx_empty:
    lw    t1, 0x08(t0)      # STATUS oku
    andi  t1, t1, 0x02      # tx_empty bit[1]
    beqz  t1, wait_tx_empty # tx_empty=0 → bekle

    li    t1, 0x41           # 'A'
    sw    t1, 0x00(t0)      # TXDATA ← 0x41
```

---

*Bu belge HexaCore-V2 SoC projesinin teknik referans dokümanıdır. RTL kaynak kodları ile senkron tutulmalıdır.*
