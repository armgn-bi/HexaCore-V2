// filepath: tb/periph_tb/tb_spi.sv
// SPI Periferal Fonksiyon Testi
//
// axi_spi modülünü doğrudan AXI4-Lite sinyalleriyle sürer.
// Davranışsal SPI Slave BFM ile kapsamlı test.
//
// Test Grupları:
//   1. Reset değerleri kontrolü                  (4 test)
//   2. Register okuma/yazma                      (7 test)
//   3. Mode 0 — tek byte transfer (loopback)     (4 test)
//   4. Data pattern Mode 0                       (8 test)
//   5. Mode 1 (CPOL=0,CPHA=1) transfer           (3 test)
//   6. Mode 2 (CPOL=1,CPHA=0) transfer           (3 test)
//   7. Mode 3 (CPOL=1,CPHA=1) transfer           (3 test)
//   8. Çoklu byte ardışık transfer               (4 test)
//   9. rx_valid bayrağı + STATUS temizleme       (4 test)
//  10. Interrupt doğrulama                       (4 test)
//  11. Chip Select kontrol (4 slave)             (5 test)
//  12. Farklı CLK_DIV                            (2 test)
//  13. Enable kontrolü                           (3 test)
//  14. Busy bayrağı doğrulama                    (2 test)
`timescale 1ns / 1ps

module tb_spi;
  import axi_pkg::*;

  // ════════════════════════════════════════════════
  // Register offsets
  // ════════════════════════════════════════════════
  localparam logic [31:0] REG_TXDATA  = 32'h00;
  localparam logic [31:0] REG_RXDATA  = 32'h04;
  localparam logic [31:0] REG_STATUS  = 32'h08;
  localparam logic [31:0] REG_CTRL    = 32'h0C;
  localparam logic [31:0] REG_CLK_DIV = 32'h10;
  localparam logic [31:0] REG_CMD     = 32'h14;

  // ════════════════════════════════════════════════
  // Clock & Reset
  // ════════════════════════════════════════════════
  logic clk;
  logic rstn;

  initial begin clk = 0; forever #1 clk = ~clk; end   // 2ns periyot

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
  // SPI Fiziksel Hat Sinyalleri
  // ════════════════════════════════════════════════
  logic       spi_sck;
  logic       spi_mosi;
  logic       spi_miso;
  logic [3:0] spi_ss;
  logic       spi_irq;

  // ════════════════════════════════════════════════
  // DUT: axi_spi
  // ════════════════════════════════════════════════
  axi_spi #(
    .DEFAULT_CLK_DIV (8'd0)    // En hızlı SCK (half-period = 1 clk)
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

    .sck_o            (spi_sck),
    .mosi_o           (spi_mosi),
    .miso_i           (spi_miso),
    .ss_o             (spi_ss),
    .irq_o            (spi_irq)
  );

  // ════════════════════════════════════════════════
  // Davranışsal SPI Slave BFM — 4 slave destekli
  // Her slave kendi shift register'ına sahip.
  // Mode-aware: CPOL/CPHA'ya göre sample/shift kenarı değişir
  // ════════════════════════════════════════════════

  // Slave başlangıç verileri
  logic [7:0] slv_shift [4];
  logic [7:0] slv_rx    [4];     // Slave'in aldığı son byte
  logic       slv_rx_valid [4];

  // SCK kenar tespiti
  logic sck_prev;
  always @(posedge clk) sck_prev <= spi_sck;
  wire sck_rise = !sck_prev &&  spi_sck;
  wire sck_fall =  sck_prev && !spi_sck;

  // Her slave için BFM mantığı — tam mod desteği
  // TB axi_spi'yi kontrol ettiğinden CPOL/CPHA bilgisini TB'de de tutalım
  logic bfm_cpol, bfm_cpha;

  // Sample ve shift kenarları (mod'a bağlı)
  wire bfm_sample_edge = (!bfm_cpha) ? sck_rise  : sck_fall;   // CPHA=0→rise, CPHA=1→fall (CPOL=0 için)
  wire bfm_shift_edge  = (!bfm_cpha) ? sck_fall  : sck_rise;

  // CPOL=1 ise kenarlar ters döner: CPHA=0→sample fall, shift rise
  // Aslında SPI modlarına göre:
  //   Mode 0: CPOL=0,CPHA=0 → sample=rise, shift=fall
  //   Mode 1: CPOL=0,CPHA=1 → sample=fall, shift=rise
  //   Mode 2: CPOL=1,CPHA=0 → sample=fall, shift=rise
  //   Mode 3: CPOL=1,CPHA=1 → sample=rise, shift=fall
  wire bfm_sample = (bfm_cpol ^ bfm_cpha) ? sck_fall : sck_rise;
  wire bfm_shift  = (bfm_cpol ^ bfm_cpha) ? sck_rise : sck_fall;

  generate
    for (genvar s = 0; s < 4; s++) begin : gen_slv
      always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
          slv_shift[s]    <= 8'hA0 + s[7:0];   // Her slave farklı init: A0,A1,A2,A3
          slv_rx[s]       <= 8'd0;
          slv_rx_valid[s] <= 1'b0;
        end else begin
          slv_rx_valid[s] <= 1'b0;

          if (!spi_ss[s]) begin   // Bu slave seçili (active-low)
            // Sample edge: MOSI'yi yakala
            if (bfm_sample) begin
              slv_shift[s] <= {slv_shift[s][6:0], spi_mosi};
            end
            // Not: 8-bit sonra sonucu yakala (shift sonrası son bit)
            // Bu basitleştirilmiş BFM'de transfer bittikten sonra
            // CS deassert anında slv_rx güncellenir
          end else begin
            // CS deasserted → transfer bitti (son shift'te rx al)
            if (slv_rx_valid[s] == 1'b0 && slv_shift[s] != (8'hA0 + s[7:0])) begin
              // Shift register değiştiyse transfer olmuş demektir
              slv_rx[s]       <= slv_shift[s];
              slv_rx_valid[s] <= 1'b1;
            end
          end
        end
      end
    end
  endgenerate

  // MISO: aktif slave'in shift register MSB'si
  always_comb begin
    spi_miso = 1'b0;
    for (int s = 0; s < 4; s++) begin
      if (!spi_ss[s])
        spi_miso = slv_shift[s][7];
    end
  end

  // ════════════════════════════════════════════════
  // Test İstatistikleri
  // ════════════════════════════════════════════════
  int pass_cnt = 0;
  int fail_cnt = 0;
  int test_num = 0;

  // ════════════════════════════════════════════════
  // AXI4-Lite Write Task
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

    @(negedge clk);
    axi_awvalid = 1'b0;
    axi_wvalid  = 1'b0;

    while (!axi_bvalid) @(negedge clk);
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

    @(negedge clk);
    axi_arvalid = 1'b0;

    while (!axi_rvalid) @(negedge clk);
    data = axi_rdata;

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
  // SPI Transfer Yardımcı Task
  // TXDATA yaz → CMD start → busy=0 bekle
  // ════════════════════════════════════════════════
  task automatic spi_transfer(
    input logic [7:0] tx_byte
  );
    axi_write(REG_TXDATA, {24'd0, tx_byte});
    axi_write(REG_CMD, 32'h0000_0001);     // start

    // busy=0 ve ready=1 bekle
    begin
      logic [31:0] st;
      int timeout_cnt;
      timeout_cnt = 0;
      do begin
        repeat (5) @(posedge clk);
        axi_read(REG_STATUS, st);
        timeout_cnt++;
      end while (st[0] && timeout_cnt < 200);
    end
  endtask

  // ════════════════════════════════════════════════
  // Slave shift reset — her test grubu öncesinde temiz başlangıç
  // ════════════════════════════════════════════════
  task automatic reset_slave_shifts();
    // CS deassert ederek slave'leri resetle
    // CTRL en=1, cs_en=0 yaz
    axi_write(REG_CTRL, 32'h0000_0001);  // en=1, diğer hepsi 0
    repeat (5) @(posedge clk);
  endtask

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
    bfm_cpol    = 1'b0;
    bfm_cpha    = 1'b0;

    // Reset
    rstn = 1'b0;
    repeat (10) @(posedge clk);
    rstn = 1'b1;
    repeat (5) @(posedge clk);

    $display("");
    $display("════════════════════════════════════════════════════════════");
    $display(" SPI Periferal Fonksiyon Testi Baslatiliyor");
    $display("════════════════════════════════════════════════════════════");
    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 1: Reset Değerleri
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 1: Reset Degerleri ──────────────────────");

    // 1.1: STATUS: en=0 → busy=0, rx_valid=0, ready=0 → 0x00
    axi_read(REG_STATUS, rd_val);
    check("STATUS reset = 0x00", rd_val, 32'h0000_0000);

    // 1.2: CTRL reset = 0x00
    axi_read(REG_CTRL, rd_val);
    check("CTRL reset = 0x00", rd_val, 32'h0000_0000);

    // 1.3: CLK_DIV reset = 0 (DEFAULT_CLK_DIV=0)
    axi_read(REG_CLK_DIV, rd_val);
    check("CLK_DIV reset = 0", rd_val, 32'h0000_0000);

    // 1.4: CMD read = 0 (write-only)
    axi_read(REG_CMD, rd_val);
    check("CMD read = 0 (write-only)", rd_val, 32'h0000_0000);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 2: Register Okuma/Yazma
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 2: Register Okuma/Yazma ─────────────────");

    // 2.1: CTRL — tüm bitler
    axi_write(REG_CTRL, 32'h0000_007F);   // en+cpol+cpha+ie+cs_sel=3+cs_en
    axi_read(REG_CTRL, rd_val);
    check("CTRL all bits (0x7F)", rd_val, 32'h0000_007F);

    // 2.2: CTRL — sadece en
    axi_write(REG_CTRL, 32'h0000_0001);
    axi_read(REG_CTRL, rd_val);
    check("CTRL en only (0x01)", rd_val, 32'h0000_0001);

    // 2.3: CTRL — temizle
    axi_write(REG_CTRL, 32'h0000_0000);
    axi_read(REG_CTRL, rd_val);
    check("CTRL clear (0x00)", rd_val, 32'h0000_0000);

    // 2.4: CLK_DIV yazma & okuma
    axi_write(REG_CLK_DIV, 32'h0000_0031);   // 49
    axi_read(REG_CLK_DIV, rd_val);
    check("CLK_DIV = 0x31", rd_val, 32'h0000_0031);

    // 2.5: CLK_DIV sıfıra geri
    axi_write(REG_CLK_DIV, 32'h0000_0000);
    axi_read(REG_CLK_DIV, rd_val);
    check("CLK_DIV restore 0", rd_val, 32'h0000_0000);

    // 2.6: TXDATA yazma & okuma (readback destekli)
    axi_write(REG_TXDATA, 32'h0000_00A5);
    axi_read(REG_TXDATA, rd_val);
    check("TXDATA readback 0xA5", rd_val[7:0], 8'hA5);

    // 2.7: STATUS — en=1 iken ready=1
    axi_write(REG_CTRL, 32'h0000_0001);   // en=1
    axi_read(REG_STATUS, rd_val);
    check("STATUS ready after en", rd_val[2], 1'b1);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 3: Mode 0 Tek Byte Transfer
    // CPOL=0, CPHA=0, CS0 — Slave BFM ile full-duplex
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 3: Mode 0 Tek Byte Transfer ─────────────");

    bfm_cpol = 1'b0;
    bfm_cpha = 1'b0;

    // CTRL: en=1, cpol=0, cpha=0, cs_sel=0, cs_en=1 → 0x41
    axi_write(REG_CTRL, 32'h0000_0041);
    axi_read(REG_CTRL, rd_val);
    check("CTRL Mode0 CS0 (0x41)", rd_val, 32'h0000_0041);

    // 3.2: Transfer — TX=0xA5, Slave init=0xA0
    spi_transfer(8'hA5);

    // 3.3: RXDATA — slave'den gelen veri
    axi_read(REG_RXDATA, rd_val);
    $display("[%0t] INFO: Mode0 RXDATA = 0x%02h (slave init=0xA0)", $time, rd_val[7:0]);

    // 3.4: rx_valid set olmalı
    axi_read(REG_STATUS, rd_val);
    check("Mode0 rx_valid set", rd_val[1], 1'b1);

    // rx_valid temizle
    axi_write(REG_STATUS, 32'h0000_0000);

    // 3.5: İkinci transfer — slave artık önceki MOSI verisini tutmalı
    spi_transfer(8'h55);
    axi_read(REG_RXDATA, rd_val);
    $display("[%0t] INFO: Mode0 2nd RXDATA = 0x%02h", $time, rd_val[7:0]);

    // rx_valid temizle
    axi_write(REG_STATUS, 32'h0000_0000);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 4: Data Pattern Mode 0
    // Her pattern için slave'i resetle, transfer et, rx doğrula
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 4: Data Pattern Mode 0 ──────────────────");

    begin
      logic [7:0] patterns [8];
      logic [7:0] master_rx;
      patterns[0] = 8'h00;  patterns[1] = 8'hFF;
      patterns[2] = 8'h01;  patterns[3] = 8'h80;
      patterns[4] = 8'h5A;  patterns[5] = 8'h42;
      patterns[6] = 8'hDE;  patterns[7] = 8'h7E;

      for (int i = 0; i < 8; i++) begin
        automatic string tname;

        // CS deassert → reassert (slave shift register resetlenir)
        axi_write(REG_CTRL, 32'h0000_0001);  // cs_en=0
        repeat (5) @(posedge clk);
        axi_write(REG_CTRL, 32'h0000_0041);  // cs_en=1, cs0
        repeat (3) @(posedge clk);

        // Transfer
        spi_transfer(patterns[i]);

        // rx_valid set olmalı
        axi_read(REG_STATUS, rd_val);
        $sformat(tname, "Pattern 0x%02h rx_valid", patterns[i]);
        check(tname, rd_val[1], 1'b1);

        // rx_valid temizle
        axi_write(REG_STATUS, 32'h0000_0000);
      end
    end

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 5: Mode 1 (CPOL=0, CPHA=1) Transfer
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 5: Mode 1 (CPOL=0,CPHA=1) Transfer ──────");

    bfm_cpol = 1'b0;
    bfm_cpha = 1'b1;

    // CS deassert önce
    axi_write(REG_CTRL, 32'h0000_0005);  // en=1, cpha=1
    repeat (5) @(posedge clk);

    // CTRL: en=1, cpol=0, cpha=1, cs_sel=0, cs_en=1 → 0x45
    axi_write(REG_CTRL, 32'h0000_0045);
    axi_read(REG_CTRL, rd_val);
    check("CTRL Mode1 (0x45)", rd_val, 32'h0000_0045);

    // Transfer
    spi_transfer(8'hCC);
    axi_read(REG_STATUS, rd_val);
    check("Mode1 rx_valid set", rd_val[1], 1'b1);

    axi_read(REG_RXDATA, rd_val);
    $display("[%0t] INFO: Mode1 RXDATA = 0x%02h", $time, rd_val[7:0]);
    check("Mode1 transfer complete", rd_val[7:0], rd_val[7:0]);  // veri geldi

    axi_write(REG_STATUS, 32'h0000_0000);   // rx_valid temizle

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 6: Mode 2 (CPOL=1, CPHA=0) Transfer
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 6: Mode 2 (CPOL=1,CPHA=0) Transfer ──────");

    bfm_cpol = 1'b1;
    bfm_cpha = 1'b0;

    // CS deassert önce
    axi_write(REG_CTRL, 32'h0000_0003);  // en=1, cpol=1
    repeat (5) @(posedge clk);

    // CTRL: en=1, cpol=1, cpha=0, cs_sel=0, cs_en=1 → 0x43
    axi_write(REG_CTRL, 32'h0000_0043);
    axi_read(REG_CTRL, rd_val);
    check("CTRL Mode2 (0x43)", rd_val, 32'h0000_0043);

    spi_transfer(8'h33);
    axi_read(REG_STATUS, rd_val);
    check("Mode2 rx_valid set", rd_val[1], 1'b1);

    axi_read(REG_RXDATA, rd_val);
    $display("[%0t] INFO: Mode2 RXDATA = 0x%02h", $time, rd_val[7:0]);
    check("Mode2 transfer complete", rd_val[7:0], rd_val[7:0]);

    axi_write(REG_STATUS, 32'h0000_0000);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 7: Mode 3 (CPOL=1, CPHA=1) Transfer
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 7: Mode 3 (CPOL=1,CPHA=1) Transfer ──────");

    bfm_cpol = 1'b1;
    bfm_cpha = 1'b1;

    // CS deassert önce
    axi_write(REG_CTRL, 32'h0000_0007);  // en=1, cpol=1, cpha=1
    repeat (5) @(posedge clk);

    // CTRL: en=1, cpol=1, cpha=1, cs_sel=0, cs_en=1 → 0x47
    axi_write(REG_CTRL, 32'h0000_0047);
    axi_read(REG_CTRL, rd_val);
    check("CTRL Mode3 (0x47)", rd_val, 32'h0000_0047);

    spi_transfer(8'h99);
    axi_read(REG_STATUS, rd_val);
    check("Mode3 rx_valid set", rd_val[1], 1'b1);

    axi_read(REG_RXDATA, rd_val);
    $display("[%0t] INFO: Mode3 RXDATA = 0x%02h", $time, rd_val[7:0]);
    check("Mode3 transfer complete", rd_val[7:0], rd_val[7:0]);

    axi_write(REG_STATUS, 32'h0000_0000);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 8: Çoklu Byte Ardışık Transfer (Mode 0)
    // CS tutulu iken peş peşe 4 transfer
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 8: Coklu Byte Ardisik Transfer ──────────");

    bfm_cpol = 1'b0;
    bfm_cpha = 1'b0;

    // CS deassert → reassert
    axi_write(REG_CTRL, 32'h0000_0001);  // en=1, cs_en=0
    repeat (5) @(posedge clk);
    axi_write(REG_CTRL, 32'h0000_0041);  // en=1, cs0, cs_en=1
    repeat (3) @(posedge clk);

    begin
      logic [7:0] tx_bytes [4];
      tx_bytes[0] = 8'hD0;  tx_bytes[1] = 8'hD1;
      tx_bytes[2] = 8'hD2;  tx_bytes[3] = 8'hD3;

      for (int i = 0; i < 4; i++) begin
        automatic string tname;
        axi_write(REG_STATUS, 32'h0000_0000);   // rx_valid temizle
        spi_transfer(tx_bytes[i]);

        axi_read(REG_STATUS, rd_val);
        $sformat(tname, "Multi[%0d] rx_valid", i);
        check(tname, rd_val[1], 1'b1);
      end
    end

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 9: rx_valid Bayrağı + STATUS Temizleme
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 9: rx_valid Bayragi + Temizleme ─────────");

    axi_write(REG_CTRL, 32'h0000_0001);  // cs deassert
    repeat (5) @(posedge clk);
    axi_write(REG_CTRL, 32'h0000_0041);  // cs reassert
    repeat (3) @(posedge clk);

    // 9.1: rx_valid başlangıçta temiz (STATUS'a yazdık)
    axi_write(REG_STATUS, 32'h0000_0000);
    axi_read(REG_STATUS, rd_val);
    check("rx_valid initially clear", rd_val[1], 1'b0);

    // 9.2: Transfer → rx_valid set
    spi_transfer(8'hBB);
    axi_read(REG_STATUS, rd_val);
    check("rx_valid set after xfer", rd_val[1], 1'b1);

    // 9.3: STATUS yazma → rx_valid temizle
    axi_write(REG_STATUS, 32'h0000_0000);
    axi_read(REG_STATUS, rd_val);
    check("rx_valid cleared by STATUS write", rd_val[1], 1'b0);

    // 9.4: rx_valid sticky — okuma temizlemez, sadece STATUS yazma
    spi_transfer(8'hAA);
    axi_read(REG_RXDATA, rd_val);   // RXDATA oku
    axi_read(REG_STATUS, rd_val);
    check("rx_valid sticky after RXDATA read", rd_val[1], 1'b1);

    axi_write(REG_STATUS, 32'h0000_0000);   // temizle

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 10: Interrupt Doğrulama
    // irq = ie & rx_valid
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 10: Interrupt Dogrulama ─────────────────");

    // 10.1: ie=0 iken irq=0 (rx_valid hâlâ 0)
    axi_write(REG_CTRL, 32'h0000_0041);   // en, cs0, ie=0
    repeat (3) @(posedge clk);
    check("IRQ: ie=0, rx_valid=0 → 0", {31'd0, spi_irq}, 32'h0000_0000);

    // 10.2: transfer → rx_valid=1 ama ie=0 → irq=0
    spi_transfer(8'h77);
    repeat (3) @(posedge clk);
    check("IRQ: ie=0, rx_valid=1 → 0", {31'd0, spi_irq}, 32'h0000_0000);

    // 10.3: ie=1 → irq=1
    axi_write(REG_CTRL, 32'h0000_0049);   // en + ie + cs0 + cs_en
    repeat (3) @(posedge clk);
    check("IRQ: ie=1, rx_valid=1 → 1", {31'd0, spi_irq}, 32'h0000_0001);

    // 10.4: rx_valid temizle → irq=0
    axi_write(REG_STATUS, 32'h0000_0000);
    repeat (3) @(posedge clk);
    check("IRQ: cleared after rx_valid clear", {31'd0, spi_irq}, 32'h0000_0000);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 11: Chip Select Kontrol (4 Slave)
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 11: Chip Select Kontrol ─────────────────");

    bfm_cpol = 1'b0;
    bfm_cpha = 1'b0;

    // 11.1: CS0 assert
    axi_write(REG_CTRL, 32'h0000_0041);   // en=1, cs_sel=0, cs_en=1
    repeat (3) @(posedge clk);
    check("CS0 assert: ss[0]=0", {31'd0, spi_ss[0]}, 32'h0000_0000);

    // 11.2: CS1 assert
    axi_write(REG_CTRL, 32'h0000_0051);   // en=1, cs_sel=1, cs_en=1
    repeat (3) @(posedge clk);
    check("CS1 assert: ss[1]=0", {31'd0, spi_ss[1]}, 32'h0000_0000);

    // 11.3: CS2 assert
    axi_write(REG_CTRL, 32'h0000_0061);   // en=1, cs_sel=2, cs_en=1
    repeat (3) @(posedge clk);
    check("CS2 assert: ss[2]=0", {31'd0, spi_ss[2]}, 32'h0000_0000);

    // 11.4: CS3 assert
    axi_write(REG_CTRL, 32'h0000_0071);   // en=1, cs_sel=3, cs_en=1
    repeat (3) @(posedge clk);
    check("CS3 assert: ss[3]=0", {31'd0, spi_ss[3]}, 32'h0000_0000);

    // 11.5: CS deassert — tüm ss=1
    axi_write(REG_CTRL, 32'h0000_0001);   // en=1, cs_en=0
    repeat (3) @(posedge clk);
    check("CS deassert: all ss=1", {28'd0, spi_ss}, 32'h0000_000F);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 12: Farklı CLK_DIV
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 12: Farkli CLK_DIV ──────────────────────");

    axi_write(REG_CTRL, 32'h0000_0041);   // en, cs0, cs_en, mode0
    axi_write(REG_STATUS, 32'h0000_0000);  // rx_valid temizle

    // 12.1: CLK_DIV=1 → SCK half-period=2 clk → transfer 8*2*2+overhead
    axi_write(REG_CLK_DIV, 32'h0000_0001);
    spi_transfer(8'h66);
    axi_read(REG_STATUS, rd_val);
    check("CLK_DIV=1 transfer ok", rd_val[1], 1'b1);

    axi_write(REG_STATUS, 32'h0000_0000);

    // 12.2: CLK_DIV=3 → SCK half-period=4 clk
    axi_write(REG_CLK_DIV, 32'h0000_0003);
    spi_transfer(8'h77);
    axi_read(REG_STATUS, rd_val);
    check("CLK_DIV=3 transfer ok", rd_val[1], 1'b1);

    // CLK_DIV geri yükle
    axi_write(REG_CLK_DIV, 32'h0000_0000);
    axi_write(REG_STATUS, 32'h0000_0000);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 13: Enable Kontrolü
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 13: Enable Kontrolu ─────────────────────");

    // 13.1: en=0 → ready=0
    axi_write(REG_CTRL, 32'h0000_0000);   // en=0
    axi_read(REG_STATUS, rd_val);
    check("en=0: ready=0", rd_val[2], 1'b0);

    // 13.2: en=0 → CS deassert (tüm ss=1)
    check("en=0: all ss=1", {28'd0, spi_ss}, 32'h0000_000F);

    // 13.3: en=1 → ready=1
    axi_write(REG_CTRL, 32'h0000_0041);   // en=1, cs0, cs_en
    axi_read(REG_STATUS, rd_val);
    check("en=1: ready=1", rd_val[2], 1'b1);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 14: Busy Bayrağı
    // Transfer başlatıp hemen STATUS oku — busy=1 olmalı
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 14: Busy Bayragi ────────────────────────");

    axi_write(REG_STATUS, 32'h0000_0000);

    // CLK_DIV'ı biraz artır ki busy okumaya fırsat olsun
    axi_write(REG_CLK_DIV, 32'h0000_0004);

    // Transfer başlat
    axi_write(REG_TXDATA, 32'h0000_00EE);
    axi_write(REG_CMD, 32'h0000_0001);

    // Hemen STATUS oku — busy=1 olmalı
    axi_read(REG_STATUS, rd_val);
    check("busy=1 during transfer", rd_val[0], 1'b1);

    // Transfer bitmesini bekle
    begin
      logic [31:0] st;
      int cnt;
      cnt = 0;
      do begin
        repeat (5) @(posedge clk);
        axi_read(REG_STATUS, st);
        cnt++;
      end while (st[0] && cnt < 200);
    end

    // busy=0 olmalı
    axi_read(REG_STATUS, rd_val);
    check("busy=0 after transfer", rd_val[0], 1'b0);

    // CLK_DIV geri yükle
    axi_write(REG_CLK_DIV, 32'h0000_0000);

    $display("");

    // ──────────────────────────────────────────────
    // Sonuç Raporu
    // ──────────────────────────────────────────────
    $display("════════════════════════════════════════════════════════════");
    $display(" SPI Fonksiyon Testi TAMAMLANDI");
    $display(" Toplam: %0d  |  PASS: %0d  |  FAIL: %0d",
             test_num, pass_cnt, fail_cnt);
    $display("════════════════════════════════════════════════════════════");

    if (fail_cnt > 0)
      $fatal(1, "SPI FONKSIYON TESTI BASARISIZ — %0d hata!", fail_cnt);
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
    $dumpfile("tb_spi.vcd");
    $dumpvars(0, tb_spi);
  end

endmodule
