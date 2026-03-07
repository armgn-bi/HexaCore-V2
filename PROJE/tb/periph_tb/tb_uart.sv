// filepath: tb/periph_tb/tb_uart.sv
// UART Periferal Fonksiyon Testi
//
// axi_uart modülünü doğrudan AXI4-Lite sinyalleriyle sürer.
// TX→RX loopback ve davranışsal UART BFM ile kapsamlı test.
//
// Test Grupları:
//   1. Reset değerleri kontrolü                (3 test)
//   2. Register okuma/yazma                    (6 test)
//   3. Tek byte TX→RX loopback                 (3 test)
//   4. Çoklu data pattern loopback             (8 test)
//   5. Çoklu byte ardışık loopback             (4 test)
//   6. TX FIFO doluluğu + bayraklar           (21 test)
//   7. Interrupt doğrulama                     (6 test)
//   8. Frame hatası enjeksiyonu (BFM)          (6 test)
//   9. Overrun hatası (BFM)                    (4 test)
//  10. Farklı baud rate                        (2 test)
//  11. TX/RX enable/disable kontrolü           (3 test)
//  12. Bit-seviyeli TX doğrulama (Monitor)     (2 test)
`timescale 1ns / 1ps

module tb_uart;
  import axi_pkg::*;

  // ════════════════════════════════════════════════
  // Parametreler
  // ════════════════════════════════════════════════
  localparam int BIT_PERIOD  = 16;          // 16 tick/bit (16x oversampling)
  localparam int FRAME_CLKS  = BIT_PERIOD * 10;  // 8N1 = 10 bit = 160 clk

  // Register offsets (alt 8 bit, axi_lite_slave tarafından kesilir)
  localparam logic [31:0] REG_TXDATA   = 32'h00;
  localparam logic [31:0] REG_RXDATA   = 32'h04;
  localparam logic [31:0] REG_STATUS   = 32'h08;
  localparam logic [31:0] REG_CTRL     = 32'h0C;
  localparam logic [31:0] REG_BAUD_DIV = 32'h10;

  // ════════════════════════════════════════════════
  // Clock & Reset
  // ════════════════════════════════════════════════
  logic clk;
  logic rstn;

  initial begin clk = 0; forever #1 clk = ~clk; end   // 2ns periyot (hızlı sim)

  // ════════════════════════════════════════════════
  // AXI4-Lite Sinyalleri
  // ════════════════════════════════════════════════
  logic [AXI_ADDR_WIDTH-1:0] axi_awaddr;
  logic [2:0]                axi_awprot;
  logic                      axi_awvalid;
  logic                      axi_awready;

  logic [AXI_DATA_WIDTH-1:0] axi_wdata;
  logic [AXI_STRB_WIDTH-1:0] axi_wstrb;
  logic                      axi_wvalid;
  logic                      axi_wready;

  logic [1:0]                axi_bresp;
  logic                      axi_bvalid;
  logic                      axi_bready;

  logic [AXI_ADDR_WIDTH-1:0] axi_araddr;
  logic [2:0]                axi_arprot;
  logic                      axi_arvalid;
  logic                      axi_arready;

  logic [AXI_DATA_WIDTH-1:0] axi_rdata;
  logic [1:0]                axi_rresp;
  logic                      axi_rvalid;
  logic                      axi_rready;

  // ════════════════════════════════════════════════
  // UART Fiziksel Hat Sinyalleri
  // ════════════════════════════════════════════════
  logic uart_tx_wire;         // DUT TX çıkışı
  logic uart_rx_wire;         // DUT RX girişi
  logic uart_irq_wire;        // DUT interrupt çıkışı

  // ── Loopback / BFM MUX ──
  logic rx_mux_sel;           // 0 = loopback (tx→rx), 1 = BFM çıkışı
  logic bfm_rx_line;          // BFM UART TX çıkışı → DUT RX girişi

  assign uart_rx_wire = rx_mux_sel ? bfm_rx_line : uart_tx_wire;

  // ════════════════════════════════════════════════
  // DUT: axi_uart
  // ════════════════════════════════════════════════
  axi_uart #(
    .DEFAULT_BAUD_DIV (16'd0),     // En hızlı baud (tick her cycle)
    .TX_FIFO_DEPTH    (16),
    .RX_FIFO_DEPTH    (16)
  ) u_dut (
    .clk_i            (clk),
    .rstn_i           (rstn),

    .s_axi_awaddr_i   (axi_awaddr),
    .s_axi_awprot_i   (axi_awprot),
    .s_axi_awvalid_i  (axi_awvalid),
    .s_axi_awready_o  (axi_awready),

    .s_axi_wdata_i    (axi_wdata),
    .s_axi_wstrb_i    (axi_wstrb),
    .s_axi_wvalid_i   (axi_wvalid),
    .s_axi_wready_o   (axi_wready),

    .s_axi_bresp_o    (axi_bresp),
    .s_axi_bvalid_o   (axi_bvalid),
    .s_axi_bready_i   (axi_bready),

    .s_axi_araddr_i   (axi_araddr),
    .s_axi_arprot_i   (axi_arprot),
    .s_axi_arvalid_i  (axi_arvalid),
    .s_axi_arready_o  (axi_arready),

    .s_axi_rdata_o    (axi_rdata),
    .s_axi_rresp_o    (axi_rresp),
    .s_axi_rvalid_o   (axi_rvalid),
    .s_axi_rready_i   (axi_rready),

    .tx_o             (uart_tx_wire),
    .rx_i             (uart_rx_wire),
    .irq_o            (uart_irq_wire)
  );

  // ════════════════════════════════════════════════
  // Test İstatistikleri
  // ════════════════════════════════════════════════
  int pass_cnt = 0;
  int fail_cnt = 0;
  int test_num = 0;

  // ════════════════════════════════════════════════
  // AXI4-Lite Write Task
  // negedge'de sürer — posedge'de DUT örnekler
  // ════════════════════════════════════════════════
  task automatic axi_write(
    input logic [31:0] addr,
    input logic [31:0] data
  );
    @(negedge clk);
    axi_awaddr  = addr;
    axi_awprot  = 3'b000;
    axi_awvalid = 1'b1;
    axi_wdata   = data;
    axi_wstrb   = 4'hF;
    axi_wvalid  = 1'b1;
    axi_bready  = 1'b1;

    // Posedge: AW+W handshake (DUT'un ready'si başlangıçta 1)
    @(negedge clk);
    axi_awvalid = 1'b0;
    axi_wvalid  = 1'b0;

    // BRESP bekle
    while (!axi_bvalid) @(negedge clk);

    // BRESP alındı, cleanup
    @(negedge clk);
    axi_bready = 1'b0;
  endtask

  // ════════════════════════════════════════════════
  // AXI4-Lite Read Task
  // ════════════════════════════════════════════════
  task automatic axi_read(
    input  logic [31:0] addr,
    output logic [31:0] data
  );
    @(negedge clk);
    axi_araddr  = addr;
    axi_arprot  = 3'b000;
    axi_arvalid = 1'b1;
    axi_rready  = 1'b1;

    // Posedge: AR handshake
    @(negedge clk);
    axi_arvalid = 1'b0;

    // RRESP bekle
    while (!axi_rvalid) @(negedge clk);
    data = axi_rdata;

    // Cleanup
    @(negedge clk);
    axi_rready = 1'b0;
  endtask

  // ════════════════════════════════════════════════
  // Check Task
  // ════════════════════════════════════════════════
  task automatic check(
    input string       test_name,
    input logic [31:0] got,
    input logic [31:0] expected
  );
    test_num++;
    if (got === expected) begin
      pass_cnt++;
      $display("[%0t] PASS #%0d %s — got=0x%08h", $time, test_num, test_name, got);
    end else begin
      fail_cnt++;
      $display("[%0t] FAIL #%0d %s — got=0x%08h expected=0x%08h",
               $time, test_num, test_name, got, expected);
    end
  endtask

  // ════════════════════════════════════════════════
  // Davranışsal UART TX BFM
  // DUT'un RX girişine seri veri enjekte eder
  // BAUD_DIV=0 ile uyumlu: her bit 16 clock cycle
  // ════════════════════════════════════════════════
  task automatic uart_bfm_send(
    input logic [7:0] data,
    input bit         inject_frame_err   // 1 = stop bit'i 0 yap
  );
    integer i;
    // Start bit
    bfm_rx_line = 1'b0;
    repeat (BIT_PERIOD) @(posedge clk);

    // Data bits (LSB first)
    for (i = 0; i < 8; i++) begin
      bfm_rx_line = data[i];
      repeat (BIT_PERIOD) @(posedge clk);
    end

    // Stop bit
    bfm_rx_line = inject_frame_err ? 1'b0 : 1'b1;
    repeat (BIT_PERIOD) @(posedge clk);

    // İdle'a dön
    bfm_rx_line = 1'b1;
  endtask

  // ════════════════════════════════════════════════
  // Loopback bekle yardımcısı
  // BAUD_DIV=0 ile bir frame = 160 cycle + marj
  // ════════════════════════════════════════════════
  task automatic wait_tx_complete(int num_frames = 1);
    repeat ((FRAME_CLKS + 40) * num_frames) @(posedge clk);
  endtask

  // ════════════════════════════════════════════════
  // Davranışsal UART RX Monitor
  // DUT'un TX çıkışını yakalar, kuyruğa ekler
  // ════════════════════════════════════════════════
  logic [7:0] rx_mon_queue [$];
  logic [7:0] rx_mon_captured;
  logic       rx_mon_frame_err;

  initial begin
    // Reset bitene kadar bekle
    repeat (20) @(posedge clk);
    forever begin
      // Start bit (düşen kenar) bekle
      @(negedge uart_tx_wire);

      // Start bit ortasına git (8 tick)
      repeat (BIT_PERIOD / 2) @(posedge clk);

      // Start bit doğrula
      if (uart_tx_wire === 1'b0) begin
        // 8 data bit örnekle (her bit 16 tick sonra merkez)
        for (int i = 0; i < 8; i++) begin
          repeat (BIT_PERIOD) @(posedge clk);
          rx_mon_captured[i] = uart_tx_wire;
        end

        // Stop bit örnekle
        repeat (BIT_PERIOD) @(posedge clk);
        rx_mon_frame_err = (uart_tx_wire !== 1'b1);

        // Kuyruğa ekle
        rx_mon_queue.push_back(rx_mon_captured);
      end
      // else: yanlış alarm → geri dön
    end
  end

  // ════════════════════════════════════════════════
  // Ana Test Sekansı
  // ════════════════════════════════════════════════
  logic [31:0] rd_val;

  initial begin
    // Varsayılan sinyal değerleri
    axi_awaddr  = '0;
    axi_awprot  = '0;
    axi_awvalid = 1'b0;
    axi_wdata   = '0;
    axi_wstrb   = '0;
    axi_wvalid  = 1'b0;
    axi_bready  = 1'b0;
    axi_araddr  = '0;
    axi_arprot  = '0;
    axi_arvalid = 1'b0;
    axi_rready  = 1'b0;
    rx_mux_sel  = 1'b0;     // Loopback mode
    bfm_rx_line = 1'b1;     // UART idle = high

    // Reset
    rstn = 1'b0;
    repeat (10) @(posedge clk);
    rstn = 1'b1;
    repeat (5) @(posedge clk);

    $display("");
    $display("════════════════════════════════════════════════════════════");
    $display(" UART Periferal Fonksiyon Testi Baslatiliyor");
    $display("════════════════════════════════════════════════════════════");
    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 1: Reset Değerleri
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 1: Reset Degerleri ──────────────────────");

    // 1.1: STATUS: tx_empty=1(bit1), rx_empty=1(bit3) → 0x0A
    axi_read(REG_STATUS, rd_val);
    check("STATUS reset = 0x0A", rd_val, 32'h0000_000A);

    // 1.2: CTRL reset = 0x00
    axi_read(REG_CTRL, rd_val);
    check("CTRL reset = 0x00", rd_val, 32'h0000_0000);

    // 1.3: BAUD_DIV reset = DEFAULT (0)
    axi_read(REG_BAUD_DIV, rd_val);
    check("BAUD_DIV reset = 0", rd_val, 32'h0000_0000);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 2: Register Okuma/Yazma
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 2: Register Okuma/Yazma ─────────────────");

    // 2.1: CTRL — tüm bitler
    axi_write(REG_CTRL, 32'h0000_000F);  // tx_en + rx_en + tx_ie + rx_ie
    axi_read(REG_CTRL, rd_val);
    check("CTRL all bits set (0x0F)", rd_val, 32'h0000_000F);

    // 2.2: CTRL — sadece tx_en
    axi_write(REG_CTRL, 32'h0000_0001);
    axi_read(REG_CTRL, rd_val);
    check("CTRL tx_en only (0x01)", rd_val, 32'h0000_0001);

    // 2.3: CTRL — temizle
    axi_write(REG_CTRL, 32'h0000_0000);
    axi_read(REG_CTRL, rd_val);
    check("CTRL clear (0x00)", rd_val, 32'h0000_0000);

    // 2.4: BAUD_DIV — 115200@100MHz
    axi_write(REG_BAUD_DIV, 32'h0000_0035);
    axi_read(REG_BAUD_DIV, rd_val);
    check("BAUD_DIV = 0x35", rd_val, 32'h0000_0035);

    // 2.5: BAUD_DIV — sıfıra dön (test hızı için)
    axi_write(REG_BAUD_DIV, 32'h0000_0000);
    axi_read(REG_BAUD_DIV, rd_val);
    check("BAUD_DIV restore 0", rd_val, 32'h0000_0000);

    // 2.6: TXDATA read → 0 (write-only register)
    axi_read(REG_TXDATA, rd_val);
    check("TXDATA read = 0 (write-only)", rd_val, 32'h0000_0000);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 3: Tek Byte TX→RX Loopback
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 3: Tek Byte Loopback ────────────────────");

    // TX + RX etkinleştir
    axi_write(REG_CTRL, 32'h0000_0003);   // tx_en=1, rx_en=1

    // 3.1: 0x55
    axi_write(REG_TXDATA, 32'h0000_0055);
    wait_tx_complete(1);
    axi_read(REG_RXDATA, rd_val);
    check("Loopback 0x55", rd_val[7:0], 8'h55);

    // 3.2: 0xAA
    axi_write(REG_TXDATA, 32'h0000_00AA);
    wait_tx_complete(1);
    axi_read(REG_RXDATA, rd_val);
    check("Loopback 0xAA", rd_val[7:0], 8'hAA);

    // 3.3: 0xA5
    axi_write(REG_TXDATA, 32'h0000_00A5);
    wait_tx_complete(1);
    axi_read(REG_RXDATA, rd_val);
    check("Loopback 0xA5", rd_val[7:0], 8'hA5);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 4: Data Pattern Loopback
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 4: Data Pattern Loopback ────────────────");

    begin
      logic [7:0] patterns [8];
      patterns[0] = 8'h00;  patterns[1] = 8'hFF;
      patterns[2] = 8'h01;  patterns[3] = 8'h80;
      patterns[4] = 8'h5A;  patterns[5] = 8'h42;
      patterns[6] = 8'hDE;  patterns[7] = 8'h7E;

      for (int i = 0; i < 8; i++) begin
        automatic string tname;
        axi_write(REG_TXDATA, {24'd0, patterns[i]});
        wait_tx_complete(1);
        axi_read(REG_RXDATA, rd_val);
        $sformat(tname, "Pattern 0x%02h loopback", patterns[i]);
        check(tname, rd_val[7:0], {24'd0, patterns[i]});
      end
    end

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 5: Çoklu Byte Ardışık Loopback
    // TX FIFO'ya 4 byte yaz → otomatik gönderim → sırayla oku
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 5: Coklu Byte Ardisik Loopback ──────────");

    for (int i = 0; i < 4; i++)
      axi_write(REG_TXDATA, {24'd0, 8'hB0 + i[7:0]});

    wait_tx_complete(4);

    for (int i = 0; i < 4; i++) begin
      automatic string tname;
      axi_read(REG_RXDATA, rd_val);
      $sformat(tname, "Multi-byte[%0d]=0x%02h", i, 8'hB0 + i[7:0]);
      check(tname, rd_val[7:0], {24'd0, 8'hB0 + i[7:0]});
    end

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 6: TX FIFO Bayrakları
    // TX'i devre dışı bırakarak FIFO'yu doldur, bayrak kontrol et,
    // sonra TX'i etkinleştirip hepsini loopback ile doğrula
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 6: TX FIFO Bayraklari ───────────────────");

    // 6.1: TX FIFO başlangıçta boş
    axi_read(REG_STATUS, rd_val);
    check("TX FIFO empty initial", rd_val[1], 1'b1);

    // TX devre dışı bırak (FIFO'da biriktirmek için)
    axi_write(REG_CTRL, 32'h0000_0002);   // rx_en=1, tx_en=0

    // TX FIFO'yu doldur (16 entry)
    for (int i = 0; i < 16; i++)
      axi_write(REG_TXDATA, {24'd0, 8'hC0 + i[7:0]});

    // 6.2: tx_full bayrak kontrolü
    axi_read(REG_STATUS, rd_val);
    check("TX FIFO full flag", rd_val[0], 1'b1);

    // 6.3: tx_empty = 0
    check("TX FIFO not empty", rd_val[1], 1'b0);

    // TX'i tekrar etkinleştir → veriler gönderilir (loopback ile RX FIFO'ya)
    axi_write(REG_CTRL, 32'h0000_0003);   // tx_en=1, rx_en=1
    wait_tx_complete(16);
    repeat (30) @(posedge clk);            // RX FIFO yazım marjı

    // 6.4: TX FIFO tekrar boş
    axi_read(REG_STATUS, rd_val);
    check("TX FIFO empty after drain", rd_val[1], 1'b1);

    // RX FIFO'dan 16 byte oku ve doğrula (FIFO sıralaması)
    for (int i = 0; i < 16; i++) begin
      automatic string tname;
      axi_read(REG_RXDATA, rd_val);
      $sformat(tname, "FIFO drain[%0d]=0x%02h", i, 8'hC0 + i[7:0]);
      check(tname, rd_val[7:0], {24'd0, 8'hC0 + i[7:0]});
    end

    // 6.21: RX FIFO boş
    axi_read(REG_STATUS, rd_val);
    check("RX FIFO empty after drain", rd_val[3], 1'b1);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 7: Interrupt Doğrulama
    // irq = (tx_ie & tx_empty) | (rx_ie & ~rx_empty)
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 7: Interrupt Dogrulama ──────────────────");

    // 7.1: TX empty interrupt — tx_ie=1, FIFO boş → irq=1
    axi_write(REG_CTRL, 32'h0000_0007);   // tx_en + rx_en + tx_ie
    repeat (3) @(posedge clk);
    check("IRQ: tx_ie & tx_empty = 1", {31'd0, uart_irq_wire}, 32'h0000_0001);

    // 7.2: TX FIFO'ya veri koy (tx_en=0 ile) → tx_empty=0 → irq=0
    axi_write(REG_CTRL, 32'h0000_0006);   // rx_en + tx_ie, tx_en=0
    axi_write(REG_TXDATA, 32'h0000_0042);
    repeat (3) @(posedge clk);
    check("IRQ: tx_ie & ~tx_empty = 0", {31'd0, uart_irq_wire}, 32'h0000_0000);

    // 7.3: TX etkinleştir → byte gönderilir, FIFO boşalır → irq=1
    axi_write(REG_CTRL, 32'h0000_0007);   // tx_en + rx_en + tx_ie
    wait_tx_complete(1);
    repeat (5) @(posedge clk);
    check("IRQ: tx_empty after drain = 1", {31'd0, uart_irq_wire}, 32'h0000_0001);

    // Loopback verisini temizle
    axi_read(REG_RXDATA, rd_val);

    // 7.4: RX interrupt — rx_ie=1, loopback veri geldiğinde irq=1
    axi_write(REG_CTRL, 32'h0000_000B);   // tx_en + rx_en + rx_ie
    axi_write(REG_TXDATA, 32'h0000_00F1);
    wait_tx_complete(1);
    repeat (5) @(posedge clk);
    check("IRQ: rx_ie & ~rx_empty = 1", {31'd0, uart_irq_wire}, 32'h0000_0001);

    // 7.5: RX oku → rx_empty=1 → irq=0
    axi_read(REG_RXDATA, rd_val);
    check("RX data for IRQ test = 0xF1", rd_val[7:0], 8'hF1);
    repeat (3) @(posedge clk);
    check("IRQ: cleared after RX read", {31'd0, uart_irq_wire}, 32'h0000_0000);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 8: Frame Hatası Enjeksiyonu (BFM)
    // Stop bit = 0 gönderilince frame_err sticky set olur
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 8: Frame Hatasi Enjeksiyonu ─────────────");

    // BFM moduna geç
    axi_write(REG_CTRL, 32'h0000_0003);   // tx_en + rx_en
    axi_write(REG_BAUD_DIV, 32'h0000_0000);  // BAUD_DIV=0 garanti
    rx_mux_sel = 1'b1;
    bfm_rx_line = 1'b1;   // idle
    repeat (5) @(posedge clk);

    // 8.1: frame_err başlangıçta temiz
    axi_read(REG_STATUS, rd_val);
    check("frame_err initially clear", rd_val[4], 1'b0);

    // 8.2: Kötü frame enjekte et (stop bit = 0)
    uart_bfm_send(8'hCC, 1'b1);
    repeat (20) @(posedge clk);

    axi_read(REG_STATUS, rd_val);
    check("frame_err sticky set", rd_val[4], 1'b1);

    // 8.3: STATUS'a yazarak temizle
    axi_write(REG_STATUS, 32'h0000_0000);
    axi_read(REG_STATUS, rd_val);
    check("frame_err cleared by write", rd_val[4], 1'b0);

    // 8.4: İyi frame → hata yok
    uart_bfm_send(8'hDD, 1'b0);
    repeat (20) @(posedge clk);

    axi_read(REG_STATUS, rd_val);
    check("no frame_err after good frame", rd_val[4], 1'b0);

    // 8.5: Kötü frame verisi hâlâ yakalanmış (rx_valid & !rx_full → FIFO'ya gider)
    axi_read(REG_RXDATA, rd_val);
    check("frame_err data captured (0xCC)", rd_val[7:0], 8'hCC);

    // 8.6: İyi frame verisi
    axi_read(REG_RXDATA, rd_val);
    check("good frame data (0xDD)", rd_val[7:0], 8'hDD);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 9: Overrun Hatası (BFM)
    // RX FIFO dolu iken yeni veri → overrun_err sticky
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 9: Overrun Hatasi ────────────────────────");

    // RX FIFO'yu temizle (varsa kalan)
    axi_read(REG_STATUS, rd_val);
    while (!rd_val[3]) begin
      axi_read(REG_RXDATA, rd_val);   // pop
      axi_read(REG_STATUS, rd_val);   // check empty
    end

    // 9.1: overrun_err temiz
    axi_write(REG_STATUS, 32'h0000_0000);   // sticky temizle
    axi_read(REG_STATUS, rd_val);
    check("overrun_err initially clear", rd_val[5], 1'b0);

    // 9.2: RX FIFO'yu BFM ile doldur (16 byte)
    for (int i = 0; i < 16; i++) begin
      uart_bfm_send(8'hE0 + i[7:0], 1'b0);
      repeat (5) @(posedge clk);   // frame arası boşluk
    end
    repeat (20) @(posedge clk);

    axi_read(REG_STATUS, rd_val);
    check("RX FIFO full after 16 bytes", rd_val[2], 1'b1);

    // 9.3: 17. byte → overrun
    uart_bfm_send(8'hFF, 1'b0);
    repeat (20) @(posedge clk);

    axi_read(REG_STATUS, rd_val);
    check("overrun_err sticky set", rd_val[5], 1'b1);

    // 9.4: STATUS yazarak temizle
    axi_write(REG_STATUS, 32'h0000_0000);
    axi_read(REG_STATUS, rd_val);
    check("overrun_err cleared", rd_val[5], 1'b0);

    // RX FIFO'yu boşalt
    for (int i = 0; i < 16; i++)
      axi_read(REG_RXDATA, rd_val);

    // Loopback'e dön
    rx_mux_sel = 1'b0;
    repeat (5) @(posedge clk);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 10: Farklı Baud Rate
    // Loopback ile farklı BAUD_DIV değerlerinde iletişim
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 10: Farkli Baud Rate ────────────────────");

    // 10.1: BAUD_DIV=1 → bit period = 16×2 = 32 clk
    axi_write(REG_BAUD_DIV, 32'h0000_0001);
    axi_write(REG_TXDATA, 32'h0000_0066);

    repeat (400) @(posedge clk);   // 10×32 = 320 + marj

    axi_read(REG_RXDATA, rd_val);
    check("BAUD_DIV=1 loopback 0x66", rd_val[7:0], 8'h66);

    // 10.2: BAUD_DIV=2 → bit period = 16×3 = 48 clk
    axi_write(REG_BAUD_DIV, 32'h0000_0002);
    axi_write(REG_TXDATA, 32'h0000_0077);

    repeat (600) @(posedge clk);   // 10×48 = 480 + marj

    axi_read(REG_RXDATA, rd_val);
    check("BAUD_DIV=2 loopback 0x77", rd_val[7:0], 8'h77);

    // BAUD_DIV geri yükle
    axi_write(REG_BAUD_DIV, 32'h0000_0000);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 11: TX/RX Enable Kontrolü
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 11: TX/RX Enable Kontrolu ───────────────");

    // 11.1: TX disabled → FIFO'ya yazılır ama gönderilmez
    axi_write(REG_CTRL, 32'h0000_0002);   // rx_en=1, tx_en=0
    axi_write(REG_TXDATA, 32'h0000_0088);
    repeat (250) @(posedge clk);

    axi_read(REG_STATUS, rd_val);
    check("TX disabled: RX FIFO empty", rd_val[3], 1'b1);

    // 11.2: TX tekrar etkinleştir → veri gönderilmeli
    axi_write(REG_CTRL, 32'h0000_0003);   // tx_en=1, rx_en=1
    wait_tx_complete(1);

    axi_read(REG_RXDATA, rd_val);
    check("TX re-enable: data sent 0x88", rd_val[7:0], 8'h88);

    // 11.3: RX disabled → veri gönderilse bile RX almaz
    axi_write(REG_CTRL, 32'h0000_0001);   // tx_en=1, rx_en=0
    rx_mux_sel = 1'b1;
    uart_bfm_send(8'h99, 1'b0);
    repeat (20) @(posedge clk);

    axi_read(REG_STATUS, rd_val);
    check("RX disabled: FIFO empty", rd_val[3], 1'b1);

    // Temizlik: loopback'e dön, tam enable
    rx_mux_sel = 1'b0;
    axi_write(REG_CTRL, 32'h0000_0003);
    repeat (5) @(posedge clk);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 12: Bit-Seviyeli TX Doğrulama (Monitor)
    // RX monitor kuyruğunu kullanarak DUT'un TX çıkışını doğrula
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 12: Bit-Seviyeli TX Dogrulama ───────────");

    // Monitor kuyruğunu temizle
    rx_mon_queue.delete();

    // 12.1: 0x41 ('A') gönder ve monitor ile doğrula
    axi_write(REG_TXDATA, 32'h0000_0041);
    wait_tx_complete(1);

    if (rx_mon_queue.size() > 0) begin
      automatic logic [7:0] mon_byte;
      mon_byte = rx_mon_queue.pop_front();
      check("RX Monitor captured 0x41", {24'd0, mon_byte}, 32'h0000_0041);
    end else begin
      test_num++;
      fail_cnt++;
      $display("[%0t] FAIL #%0d RX Monitor: no byte captured", $time, test_num);
    end

    // 12.2: Frame error yok
    check("RX Monitor no frame err", {31'd0, rx_mon_frame_err}, 32'h0000_0000);

    // Loopback verisini temizle
    axi_read(REG_RXDATA, rd_val);

    $display("");

    // ──────────────────────────────────────────────
    // Sonuç Raporu
    // ──────────────────────────────────────────────
    $display("════════════════════════════════════════════════════════════");
    $display(" UART Fonksiyon Testi TAMAMLANDI");
    $display(" Toplam: %0d  |  PASS: %0d  |  FAIL: %0d",
             test_num, pass_cnt, fail_cnt);
    $display("════════════════════════════════════════════════════════════");

    if (fail_cnt > 0)
      $fatal(1, "UART FONKSIYON TESTI BASARISIZ — %0d hata!", fail_cnt);
    else
      $display("[TB] TUM TESTLER BASARILI.\n");

    $finish;
  end

  // ════════════════════════════════════════════════
  // Watchdog timer
  // ════════════════════════════════════════════════
  initial begin
    #500_000;
    $fatal(1, "[WATCHDOG] Zaman asimi — test 500us icinde bitmedi!");
  end

  // ════════════════════════════════════════════════
  // Opsiyonel VCD dump
  // ════════════════════════════════════════════════
  initial begin
    $dumpfile("tb_uart.vcd");
    $dumpvars(0, tb_uart);
  end

endmodule
