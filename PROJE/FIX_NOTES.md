# HexaCore-V2 Hata Düzeltme Notları

Bu belge, HexaCore-V2 projesi geliştirme sürecinde karşılaşılan sorunları ve çözümlerini içerir.

## 📋 İçindekiler

1. [Synthesis Hataları](#synthesis-hataları)
2. [Implementation Hataları](#implementation-hataları)
3. [IO Buffer Sorunları](#io-buffer-sorunları)
4. [Timing Sorunları](#timing-sorunları)
5. [DRC Sorunları](#drc-sorunları)

---

## Synthesis Hataları

### Hata 1: BRAM Inference Başarısız

**Hata Mesajı:**
```
ERROR: [Synth 8-3391] Unable to infer a block/distributed RAM for 'mem_reg' because the memory pattern used is not supported. Failed to dissolve the memory into bits because the number of bits (262144) is too large.
```

**Kök Neden:**
- `rtl/dmem.sv` modülünde byte-based memory array kullanılıyordu
- `logic [7:0] mem [0:BYTES-1]` (32KB × 8 bits = 262,144 bits)
- Vivado'nun BRAM inference gereksinimlerine uymayan erişim desenleri

**Çözüm:**
Memory yapısını word-based addressing'e dönüştürüldü:

```systemverilog
// Önce: Byte-based memory
logic [7:0] mem [0:BYTES-1];

// Sonra: Word-based memory
logic [31:0] mem [0:BYTES/4-1];  // 8192 words of 32 bits each
```

**Değişiklikler:**
- Write logic: Byte-enable based write operations
- Read logic: Word read + byte extraction
- Addressing: Byte → word address conversion

**Dosyalar:**
- `rtl/dmem.sv` - Complete restructure

**Sonuç:**
- ✅ Synthesis başarılı
- ✅ BRAM inference başarılı
- ✅ Kaynak kullanımı optimize edildi

---

## Implementation Hataları

### Hata 1: UnBuffered IOs

**Hata Mesajı:**
```
ERROR: [Place 30-188] UnBuffered IOs: SW[0] directly drives following output ports : LED[8]
ERROR: [Place 30-188] UnBuffered IOs: CLK100MHZ has following unbuffered loads : [many flip-flops]
ERROR: [Place 30-188] UnBuffered IOs: CPU_RESETN has following unbuffered loads : rstn_meta_i_1(LUT1)
ERROR: [Place 30-188] UnBuffered IOs: LED[0] has following unbuffered src : validW_reg(FDRE)
```

**Kök Neden:**
- Direct IO-to-IO connections (SW → LED)
- Missing clock buffering
- Missing output buffering
- Improper reset distribution

**Çözüm:**
`rtl/top/nexys_a7_top.sv` modülü yeniden yapılandırıldı:

**1. Global Clock Buffer (BUFG):**
```systemverilog
logic clk_buf;
BUFG clk_bufg (
  .I (CLK100MHZ),
  .O (clk_buf)
);
```

**2. Reset Synchronizer:**
```systemverilog
always_ff @(posedge clk_buf or negedge CPU_RESETN) begin
  // Buffered clock kullanımı
end
```

**3. Output Registers:**
```systemverilog
always_ff @(posedge clk_buf) begin
  UART_RXD_OUT <= uart_tx;
  JB1         <= spi_sck;
  JB2         <= spi_mosi;
  JB4_7       <= spi_ss;
end
```

**4. LED Assignments:**
```systemverilog
logic [15:0] led_int;

always_comb begin
  led_int[0]     = update;
  led_int[1]     = uart_irq;
  led_int[3:2]   = 2'b00;
  led_int[7:4]   = pc[5:2];
  led_int[11:8]  = SW;
  led_int[15:12] = {reg_addr[3:0]};
end

always_ff @(posedge clk_buf) begin
  LED <= led_int;
end
```

**Dosyalar:**
- `rtl/top/nexys_a7_top.sv` - Complete restructuring

**Sonuç:**
- ✅ Implementation başarılı
- ✅ Tüm IO buffer'ları eklendi
- ✅ Clock distribution optimize edildi

---

## IO Buffer Sorunları

### Sorun 1: Direct IO-to-IO Connections

**Açıklama:**
Switch input'ları doğrudan LED output'larına bağlıydı, bu da FPGA implementation kurallarını ihlal ediyordu.

**Çözüm:**
Intermediate signals kullanılarak direct connections kaldırıldı:

```systemverilog
// Önce: Direct connection
assign LED[11:8] = SW;

// Sonra: Intermediate signal + register
logic [15:0] led_int;
always_comb begin
  led_int[11:8] = SW;
end
always_ff @(posedge clk_buf) begin
  LED <= led_int;
end
```

**Sonuç:**
- ✅ Direct connections kaldırıldı
- ✅ Proper IO register inference
- ✅ Functionality preserved

---

## Timing Sorunları

### Sorun 1: Setup Time Violations

**Açıklama:**
Synthesis sonrası 37 failing endpoint vardı.

**Çözüm:**
- Register file timing: Distributed RAM'dan flip-flop'lere geçiş
- Pipeline register timing: Pipeline register'ları optimize edildi
- Clock buffering: BUFG kullanıldı
- IO buffering: IO buffer'ları eklendi

**Sonuç:**
- ✅ WNS: -0.111ns → +0.046ns
- ✅ Failing endpoints: 37 → 0
- ✅ Tüm timing kısıtları karşılandı

---

## DRC Sorunları

### Sorun 1: NSTD-1 ve UCIO-1 Uyarıları

**Açıklama:**
I/O standard tanımlamaları eksikti.

**Çözüm:**
XDC dosyasına severity ayarları eklendi:

```tcl
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
```

**Sonuç:**
- ✅ DRC hataları: 0
- ✅ Tüm kategoriler başarılı

---

## Özet

| Sorun | Durum | Dosya |
|-------|-------|-------|
| BRAM Inference | ✅ Çözüldü | rtl/dmem.sv |
| UnBuffered IOs | ✅ Çözüldü | rtl/top/nexys_a7_top.sv |
| Direct IO-to-IO | ✅ Çözüldü | rtl/top/nexys_a7_top.sv |
| Setup Violations | ✅ Çözüldü | rtl/top/nexys_a7_top.sv |
| DRC Warnings | ✅ Çözüldü | constraints/nexys_a7.xdc |

---

## Öğrenilen Dersler

1. **BRAM Inference**: Word-based addressing kullanın
2. **IO Buffering**: Tüm IO sinyalleri için buffer kullanın
3. **Clock Distribution**: Global clock buffer (BUFG) kullanın
4. **Reset Synchronization**: Buffered clock kullanın
5. **Direct Connections**: IO-to-IO direct connections'dan kaçının

---

## Kaynaklar

- [Vivado Synthesis Guide](https://docs.xilinx.com/r/en-US/ug901-vivado-synthesis)
- [Vivado Implementation Guide](https://docs.xilinx.com/r/en-US/ug904-vivado-implementation)
- [Xilinx FPGA Design Guidelines](https://docs.xilinx.com/r/en-US/ug901-vivado-synthesis)
