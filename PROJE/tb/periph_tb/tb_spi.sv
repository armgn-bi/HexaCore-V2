// filepath: tb/periph_tb/tb_spi.sv
// ═══════════════════════════════════════════════════════════════════
// SPI Periferal Kapsamlı Fonksiyon Testi
//
// Analog Devices SPI Interface spesifikasyonuna uygunluk doğrulaması:
//   https://www.analog.com/en/resources/analog-dialogue/articles/introduction-to-spi-interface.html
//
// axi_spi modülünü doğrudan AXI4-Lite sinyalleriyle sürer.
// Gelişmiş SPI Slave BFM:
//   • Ayrı TX / RX shift register → tam full-duplex doğrulama
//   • CPHA=1 modlarında ilk shift kenarında kaydırma atlanır
//   • CLK_DIV=4 ile 2-FF MISO senkronizasyonu için uygun zamanlama
//   • 4 bağımsız slave desteği
//
// Test Grupları:
//   1.  Reset değerleri kontrolü                  (5 test)
//   2.  Register okuma/yazma                      (8 test)
//   3.  Mode 0 — full-duplex transfer             (12 test)
//   4.  Mode 1 — full-duplex transfer             (12 test)
//   5.  Mode 2 — full-duplex transfer             (12 test)
//   6.  Mode 3 — full-duplex transfer             (12 test)
//   7.  Çoklu byte ardışık transfer               (5 test)
//   8.  rx_valid bayrağı + STATUS temizleme       (5 test)
//   9.  Interrupt doğrulama                       (5 test)
//  10.  Chip Select kontrol (4 slave)             (6 test)
//  11.  Farklı CLK_DIV                            (3 test)
//  12.  Enable kontrolü                           (3 test)
//  13.  Busy bayrağı doğrulama                    (3 test)
// ═══════════════════════════════════════════════════════════════════
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

  // Sabit CLK_DIV değeri — 2-FF senkronizasyonu için yeterli marj
  localparam int SIM_CLK_DIV = 4;

  // ════════════════════════════════════════════════
  // Clock & Reset
  // ════════════════════════════════════════════════
  logic clk;
  logic rstn;

  initial begin clk = 0; forever #5 clk = ~clk; end   // 10ns periyot (100 MHz)

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
    .DEFAULT_CLK_DIV (SIM_CLK_DIV)
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

  // ════════════════════════════════════════════════════════════════
  //  Gelişmiş SPI Slave BFM — 4 slave, ayrı TX/RX, mod-farkındalıklı
  //
  //  TX shift register: Slave'in master'a göndereceği veri (MISO)
  //  RX shift register: Slave'in master'dan aldığı veri (MOSI)
  //
  //  CPHA=0: İlk bit, CS assert anında MISO'da hazır
  //          Sample = leading edge, Shift = trailing edge
  //  CPHA=1: İlk bit, leading edge'de MISO'ya konur (shift atlanır)
  //          Shift = leading edge (ilk hariç), Sample = trailing edge
  // ════════════════════════════════════════════════════════════════

  logic        bfm_cpol, bfm_cpha;

  // Slave BFM yazmaçları
  logic [7:0]  slv_preload  [4];   // Transfer öncesi yüklenen TX verisi
  logic [7:0]  slv_tx_sr    [4];   // TX shift register
  logic [7:0]  slv_rx_sr    [4];   // RX shift register
  logic [7:0]  slv_rx_cap   [4];   // Yakalanan RX verisi (transfer sonrası)
  logic [2:0]  slv_bit_cnt  [4];   // Bit sayacı
  logic        slv_cs_prev  [4];   // Önceki CS durumu (kenar tespiti)
  logic        slv_first_shift [4]; // CPHA=1 için ilk shift izlemesi

  // SCK kenar tespiti
  logic sck_prev;
  always @(posedge clk) sck_prev <= spi_sck;
  wire sck_rise = !sck_prev &&  spi_sck;
  wire sck_fall =  sck_prev && !spi_sck;

  // Mod'a göre sample ve shift kenarları
  //   Mode 0 (CPOL=0,CPHA=0): sample=rise, shift=fall  (XOR=0)
  //   Mode 1 (CPOL=0,CPHA=1): sample=fall, shift=rise  (XOR=1)
  //   Mode 2 (CPOL=1,CPHA=0): sample=fall, shift=rise  (XOR=1)
  //   Mode 3 (CPOL=1,CPHA=1): sample=rise, shift=fall  (XOR=0)
  wire bfm_sample_edge = (bfm_cpol ^ bfm_cpha) ? sck_fall : sck_rise;
  wire bfm_shift_edge  = (bfm_cpol ^ bfm_cpha) ? sck_rise : sck_fall;

  generate
    for (genvar s = 0; s < 4; s++) begin : gen_slv
      always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
          slv_tx_sr[s]       <= 8'h00;
          slv_rx_sr[s]       <= 8'h00;
          slv_rx_cap[s]      <= 8'h00;
          slv_bit_cnt[s]     <= 3'd0;
          slv_cs_prev[s]     <= 1'b1;
          slv_first_shift[s] <= 1'b0;
        end else begin
          slv_cs_prev[s] <= spi_ss[s];

          // ── CS düşen kenar: yeni transfer başlangıcı ──
          if (slv_cs_prev[s] && !spi_ss[s]) begin
            slv_tx_sr[s]       <= slv_preload[s];
            slv_rx_sr[s]       <= 8'h00;
            slv_bit_cnt[s]     <= 3'd0;
            slv_first_shift[s] <= 1'b0;
          end

          // ── CS yükselen kenar: transfer tamamlandı → RX yakala ──
          else if (!slv_cs_prev[s] && spi_ss[s]) begin
            slv_rx_cap[s] <= slv_rx_sr[s];
          end

          // ── CS aktif iken SCK kenarlarını işle ──
          else if (!spi_ss[s]) begin

            // Sample kenarı: MOSI'yi RX shift register'a al
            if (bfm_sample_edge) begin
              slv_rx_sr[s]   <= {slv_rx_sr[s][6:0], spi_mosi};
              slv_bit_cnt[s] <= slv_bit_cnt[s] + 3'd1;
            end

            // Shift kenarı: TX shift register'ı kaydır (MISO güncelle)
            if (bfm_shift_edge) begin
              if (!bfm_cpha) begin
                // CPHA=0: her shift kenarında kaydır
                slv_tx_sr[s] <= {slv_tx_sr[s][6:0], 1'b0};
              end else begin
                // CPHA=1: ilk shift kenarını atla (MSB zaten yüklü)
                if (slv_first_shift[s]) begin
                  slv_tx_sr[s] <= {slv_tx_sr[s][6:0], 1'b0};
                end
                slv_first_shift[s] <= 1'b1;
              end
            end
          end
        end
      end
    end
  endgenerate

  // MISO: aktif slave'in TX shift register MSB'si
  always_comb begin
    spi_miso = 1'b0;
    for (int s = 0; s < 4; s++) begin
      if (!spi_ss[s])
        spi_miso = slv_tx_sr[s][7];
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
  // Check Task — PASS/FAIL raporu
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
  // SPI Transfer Yardımcı Task — TXDATA yaz → CMD start → busy=0 bekle
  // ════════════════════════════════════════════════
  task automatic spi_transfer(
    input logic [7:0] tx_byte
  );
    axi_write(REG_TXDATA, {24'd0, tx_byte});
    axi_write(REG_CMD, 32'h0000_0001);

    begin
      logic [31:0] st;
      int timeout_cnt;
      timeout_cnt = 0;
      do begin
        repeat (5) @(posedge clk);
        axi_read(REG_STATUS, st);
        timeout_cnt++;
      end while (st[0] && timeout_cnt < 500);
    end
  endtask

  // ════════════════════════════════════════════════
  // Mod Yapılandırma Task
  // ════════════════════════════════════════════════
  task automatic configure_mode(
    input logic       cpol,
    input logic       cpha,
    input logic [1:0] cs_sel,
    input logic       cs_en
  );
    logic [31:0] ctrl_val;
    ctrl_val = {25'd0, cs_en, cs_sel, 1'b0, cpha, cpol, 1'b1};

    bfm_cpol = cpol;
    bfm_cpha = cpha;

    axi_write(REG_CTRL, ctrl_val);
  endtask

  // ════════════════════════════════════════════════
  // Full-Duplex Transfer & Doğrulama Task
  // Master TX → Slave RX doğrulama + Slave TX → Master RX doğrulama
  // ════════════════════════════════════════════════
  task automatic test_full_duplex(
    input string       test_name,
    input logic        cpol,
    input logic        cpha,
    input logic [1:0]  cs_sel,
    input logic [7:0]  master_tx,
    input logic [7:0]  slave_tx
  );
    logic [31:0] rd_val;

    // 1. CS deassert → yeni transfer için temiz başlangıç
    configure_mode(cpol, cpha, cs_sel, 1'b0);
    repeat (5) @(posedge clk);

    // 2. Slave TX verisini yükle
    slv_preload[cs_sel] = slave_tx;

    // 3. CS assert
    configure_mode(cpol, cpha, cs_sel, 1'b1);
    repeat (5) @(posedge clk);

    // 4. rx_valid temizle
    axi_write(REG_STATUS, 32'h0000_0000);

    // 5. Transfer yap
    spi_transfer(master_tx);

    // 6. rx_valid kontrol
    axi_read(REG_STATUS, rd_val);
    if (!rd_val[1]) begin
      test_num++;
      fail_cnt++;
      $display("[%0t] FAIL #%0d %s — rx_valid=0 (transfer tamamlanmadi!)", $time, test_num, test_name);
      return;
    end

    // 7. Master RX doğrulama (slave'den gelen veri)
    axi_read(REG_RXDATA, rd_val);
    check({test_name, " [Master<-Slave]"}, rd_val[7:0], {24'd0, slave_tx});

    // 8. CS deassert → slave BFM RX yakala
    configure_mode(cpol, cpha, cs_sel, 1'b0);
    repeat (5) @(posedge clk);

    // 9. Slave RX doğrulama (master'dan gelen veri)
    check({test_name, " [Slave<-Master]"}, {24'd0, slv_rx_cap[cs_sel]}, {24'd0, master_tx});

    // temizle
    axi_write(REG_STATUS, 32'h0000_0000);
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

    // Slave preload başlangıç değerleri
    slv_preload[0] = 8'hA0;
    slv_preload[1] = 8'hA1;
    slv_preload[2] = 8'hA2;
    slv_preload[3] = 8'hA3;

    // Reset
    rstn = 1'b0;
    repeat (10) @(posedge clk);
    rstn = 1'b1;
    repeat (5) @(posedge clk);

    $display("");
    $display("================================================================");
    $display(" SPI Periferal Kapsamli Fonksiyon Testi Baslatiliyor");
    $display(" Analog Devices SPI Spesifikasyonuna Uygunluk Dogrulamasi");
    $display("================================================================");
    $display("");

    // ══════════════════════════════════════════════
    // TEST GRUBU 1: Reset Değerleri (5 test)
    // ══════════════════════════════════════════════
    $display("── TEST GRUBU 1: Reset Degerleri ──────────────────────");

    axi_read(REG_STATUS, rd_val);
    check("STATUS reset = 0x00", rd_val, 32'h0000_0000);

    axi_read(REG_CTRL, rd_val);
    check("CTRL reset = 0x00", rd_val, 32'h0000_0000);

    axi_read(REG_CLK_DIV, rd_val);
    check("CLK_DIV reset = 0x04", rd_val, {24'd0, SIM_CLK_DIV[7:0]});

    axi_read(REG_CMD, rd_val);
    check("CMD read = 0 (write-only)", rd_val, 32'h0000_0000);

    axi_read(REG_RXDATA, rd_val);
    check("RXDATA reset = 0x00", rd_val, 32'h0000_0000);

    $display("");

    // ══════════════════════════════════════════════
    // TEST GRUBU 2: Register Okuma/Yazma (8 test)
    // ══════════════════════════════════════════════
    $display("── TEST GRUBU 2: Register Okuma/Yazma ─────────────────");

    axi_write(REG_CTRL, 32'h0000_007F);
    axi_read(REG_CTRL, rd_val);
    check("CTRL all bits (0x7F)", rd_val, 32'h0000_007F);

    axi_write(REG_CTRL, 32'h0000_0001);
    axi_read(REG_CTRL, rd_val);
    check("CTRL en only (0x01)", rd_val, 32'h0000_0001);

    axi_write(REG_CTRL, 32'h0000_0000);
    axi_read(REG_CTRL, rd_val);
    check("CTRL clear (0x00)", rd_val, 32'h0000_0000);

    axi_write(REG_CLK_DIV, 32'h0000_0031);
    axi_read(REG_CLK_DIV, rd_val);
    check("CLK_DIV = 0x31 (49)", rd_val, 32'h0000_0031);

    axi_write(REG_CLK_DIV, {24'd0, SIM_CLK_DIV[7:0]});
    axi_read(REG_CLK_DIV, rd_val);
    check("CLK_DIV restore", rd_val, {24'd0, SIM_CLK_DIV[7:0]});

    axi_write(REG_TXDATA, 32'h0000_00A5);
    axi_read(REG_TXDATA, rd_val);
    check("TXDATA readback 0xA5", rd_val[7:0], 8'hA5);

    axi_write(REG_CTRL, 32'h0000_0001);
    axi_read(REG_STATUS, rd_val);
    check("STATUS ready after en", rd_val[2], 1'b1);

    axi_write(REG_CTRL, 32'h0000_0007);
    axi_read(REG_CTRL, rd_val);
    check("CTRL en+cpol+cpha (0x07)", rd_val, 32'h0000_0007);

    axi_write(REG_CTRL, 32'h0000_0000);
    $display("");

    // ══════════════════════════════════════════════════════════════
    // TEST GRUBU 3: Mode 0 (CPOL=0, CPHA=0) Full-Duplex (12 test)
    // AD Spec: CLK idle=LOW, sample=rising, shift=falling
    // ══════════════════════════════════════════════════════════════
    $display("── TEST GRUBU 3: Mode 0 (CPOL=0,CPHA=0) Full-Duplex ──");
    $display("  AD Spec: CLK idle=LOW, sample=rising, shift=falling");

    test_full_duplex("M0-T01 0xA5<>0x5A", 1'b0, 1'b0, 2'd0, 8'hA5, 8'h5A);
    test_full_duplex("M0-T02 0x00<>0xFF", 1'b0, 1'b0, 2'd0, 8'h00, 8'hFF);
    test_full_duplex("M0-T03 0xFF<>0x00", 1'b0, 1'b0, 2'd0, 8'hFF, 8'h00);
    test_full_duplex("M0-T04 0x01<>0x80", 1'b0, 1'b0, 2'd0, 8'h01, 8'h80);
    test_full_duplex("M0-T05 0x80<>0x01", 1'b0, 1'b0, 2'd0, 8'h80, 8'h01);
    test_full_duplex("M0-T06 0xAA<>0x55", 1'b0, 1'b0, 2'd0, 8'hAA, 8'h55);
    test_full_duplex("M0-T07 0x55<>0xAA", 1'b0, 1'b0, 2'd0, 8'h55, 8'hAA);
    test_full_duplex("M0-T08 0x3C<>0xC3", 1'b0, 1'b0, 2'd0, 8'h3C, 8'hC3);
    test_full_duplex("M0-T09 0xDE<>0xAD", 1'b0, 1'b0, 2'd0, 8'hDE, 8'hAD);
    test_full_duplex("M0-T10 0xBE<>0xEF", 1'b0, 1'b0, 2'd0, 8'hBE, 8'hEF);
    test_full_duplex("M0-T11 0xCA<>0xFE", 1'b0, 1'b0, 2'd0, 8'hCA, 8'hFE);
    test_full_duplex("M0-T12 0x12<>0x34", 1'b0, 1'b0, 2'd0, 8'h12, 8'h34);

    $display("");

    // ══════════════════════════════════════════════════════════════
    // TEST GRUBU 4: Mode 1 (CPOL=0, CPHA=1) Full-Duplex (12 test)
    // AD Spec: CLK idle=LOW, sample=falling, shift=rising
    // ══════════════════════════════════════════════════════════════
    $display("── TEST GRUBU 4: Mode 1 (CPOL=0,CPHA=1) Full-Duplex ──");
    $display("  AD Spec: CLK idle=LOW, sample=falling, shift=rising");

    test_full_duplex("M1-T01 0xA5<>0x5A", 1'b0, 1'b1, 2'd0, 8'hA5, 8'h5A);
    test_full_duplex("M1-T02 0x00<>0xFF", 1'b0, 1'b1, 2'd0, 8'h00, 8'hFF);
    test_full_duplex("M1-T03 0xFF<>0x00", 1'b0, 1'b1, 2'd0, 8'hFF, 8'h00);
    test_full_duplex("M1-T04 0x01<>0x80", 1'b0, 1'b1, 2'd0, 8'h01, 8'h80);
    test_full_duplex("M1-T05 0x80<>0x01", 1'b0, 1'b1, 2'd0, 8'h80, 8'h01);
    test_full_duplex("M1-T06 0xAA<>0x55", 1'b0, 1'b1, 2'd0, 8'hAA, 8'h55);
    test_full_duplex("M1-T07 0x55<>0xAA", 1'b0, 1'b1, 2'd0, 8'h55, 8'hAA);
    test_full_duplex("M1-T08 0x3C<>0xC3", 1'b0, 1'b1, 2'd0, 8'h3C, 8'hC3);
    test_full_duplex("M1-T09 0xDE<>0xAD", 1'b0, 1'b1, 2'd0, 8'hDE, 8'hAD);
    test_full_duplex("M1-T10 0xBE<>0xEF", 1'b0, 1'b1, 2'd0, 8'hBE, 8'hEF);
    test_full_duplex("M1-T11 0xCA<>0xFE", 1'b0, 1'b1, 2'd0, 8'hCA, 8'hFE);
    test_full_duplex("M1-T12 0x12<>0x34", 1'b0, 1'b1, 2'd0, 8'h12, 8'h34);

    $display("");

    // ══════════════════════════════════════════════════════════════
    // TEST GRUBU 5: Mode 2 (CPOL=1, CPHA=0) Full-Duplex (12 test)
    // AD Spec: CLK idle=HIGH, sample=falling, shift=rising
    // ══════════════════════════════════════════════════════════════
    $display("── TEST GRUBU 5: Mode 2 (CPOL=1,CPHA=0) Full-Duplex ──");
    $display("  AD Spec: CLK idle=HIGH, sample=falling, shift=rising");

    test_full_duplex("M2-T01 0xA5<>0x5A", 1'b1, 1'b0, 2'd0, 8'hA5, 8'h5A);
    test_full_duplex("M2-T02 0x00<>0xFF", 1'b1, 1'b0, 2'd0, 8'h00, 8'hFF);
    test_full_duplex("M2-T03 0xFF<>0x00", 1'b1, 1'b0, 2'd0, 8'hFF, 8'h00);
    test_full_duplex("M2-T04 0x01<>0x80", 1'b1, 1'b0, 2'd0, 8'h01, 8'h80);
    test_full_duplex("M2-T05 0x80<>0x01", 1'b1, 1'b0, 2'd0, 8'h80, 8'h01);
    test_full_duplex("M2-T06 0xAA<>0x55", 1'b1, 1'b0, 2'd0, 8'hAA, 8'h55);
    test_full_duplex("M2-T07 0x55<>0xAA", 1'b1, 1'b0, 2'd0, 8'h55, 8'hAA);
    test_full_duplex("M2-T08 0x3C<>0xC3", 1'b1, 1'b0, 2'd0, 8'h3C, 8'hC3);
    test_full_duplex("M2-T09 0xDE<>0xAD", 1'b1, 1'b0, 2'd0, 8'hDE, 8'hAD);
    test_full_duplex("M2-T10 0xBE<>0xEF", 1'b1, 1'b0, 2'd0, 8'hBE, 8'hEF);
    test_full_duplex("M2-T11 0xCA<>0xFE", 1'b1, 1'b0, 2'd0, 8'hCA, 8'hFE);
    test_full_duplex("M2-T12 0x12<>0x34", 1'b1, 1'b0, 2'd0, 8'h12, 8'h34);

    $display("");

    // ══════════════════════════════════════════════════════════════
    // TEST GRUBU 6: Mode 3 (CPOL=1, CPHA=1) Full-Duplex (12 test)
    // AD Spec: CLK idle=HIGH, sample=rising, shift=falling
    // ══════════════════════════════════════════════════════════════
    $display("── TEST GRUBU 6: Mode 3 (CPOL=1,CPHA=1) Full-Duplex ──");
    $display("  AD Spec: CLK idle=HIGH, sample=rising, shift=falling");

    test_full_duplex("M3-T01 0xA5<>0x5A", 1'b1, 1'b1, 2'd0, 8'hA5, 8'h5A);
    test_full_duplex("M3-T02 0x00<>0xFF", 1'b1, 1'b1, 2'd0, 8'h00, 8'hFF);
    test_full_duplex("M3-T03 0xFF<>0x00", 1'b1, 1'b1, 2'd0, 8'hFF, 8'h00);
    test_full_duplex("M3-T04 0x01<>0x80", 1'b1, 1'b1, 2'd0, 8'h01, 8'h80);
    test_full_duplex("M3-T05 0x80<>0x01", 1'b1, 1'b1, 2'd0, 8'h80, 8'h01);
    test_full_duplex("M3-T06 0xAA<>0x55", 1'b1, 1'b1, 2'd0, 8'hAA, 8'h55);
    test_full_duplex("M3-T07 0x55<>0xAA", 1'b1, 1'b1, 2'd0, 8'h55, 8'hAA);
    test_full_duplex("M3-T08 0x3C<>0xC3", 1'b1, 1'b1, 2'd0, 8'h3C, 8'hC3);
    test_full_duplex("M3-T09 0xDE<>0xAD", 1'b1, 1'b1, 2'd0, 8'hDE, 8'hAD);
    test_full_duplex("M3-T10 0xBE<>0xEF", 1'b1, 1'b1, 2'd0, 8'hBE, 8'hEF);
    test_full_duplex("M3-T11 0xCA<>0xFE", 1'b1, 1'b1, 2'd0, 8'hCA, 8'hFE);
    test_full_duplex("M3-T12 0x12<>0x34", 1'b1, 1'b1, 2'd0, 8'h12, 8'h34);

    $display("");

    // ══════════════════════════════════════════════════════════════
    // TEST GRUBU 7: Çoklu Byte Ardışık Transfer (5 test) — Mode 0
    // ══════════════════════════════════════════════════════════════
    $display("── TEST GRUBU 7: Coklu Byte Ardisik Transfer ──────────");

    bfm_cpol = 1'b0;
    bfm_cpha = 1'b0;

    configure_mode(1'b0, 1'b0, 2'd0, 1'b0);
    repeat (5) @(posedge clk);
    slv_preload[0] = 8'hB0;
    configure_mode(1'b0, 1'b0, 2'd0, 1'b1);
    repeat (5) @(posedge clk);
    axi_write(REG_STATUS, 32'h0000_0000);

    begin
      logic [7:0] tx_bytes [5];
      tx_bytes[0] = 8'hD0; tx_bytes[1] = 8'hD1;
      tx_bytes[2] = 8'hD2; tx_bytes[3] = 8'hD3; tx_bytes[4] = 8'hD4;

      for (int i = 0; i < 5; i++) begin
        automatic string tname;
        axi_write(REG_STATUS, 32'h0000_0000);
        spi_transfer(tx_bytes[i]);

        axi_read(REG_STATUS, rd_val);
        $sformat(tname, "Multi[%0d] TX=0x%02h rx_valid", i, tx_bytes[i]);
        check(tname, rd_val[1], 1'b1);
      end
    end

    $display("");

    // ══════════════════════════════════════════════════════════════
    // TEST GRUBU 8: rx_valid Bayrağı + STATUS Temizleme (5 test)
    // ══════════════════════════════════════════════════════════════
    $display("── TEST GRUBU 8: rx_valid Bayragi + Temizleme ─────────");

    configure_mode(1'b0, 1'b0, 2'd0, 1'b0);
    repeat (5) @(posedge clk);
    slv_preload[0] = 8'hCC;
    configure_mode(1'b0, 1'b0, 2'd0, 1'b1);
    repeat (5) @(posedge clk);

    axi_write(REG_STATUS, 32'h0000_0000);
    axi_read(REG_STATUS, rd_val);
    check("rx_valid initially clear", rd_val[1], 1'b0);

    spi_transfer(8'hBB);
    axi_read(REG_STATUS, rd_val);
    check("rx_valid set after xfer", rd_val[1], 1'b1);

    axi_write(REG_STATUS, 32'h0000_0000);
    axi_read(REG_STATUS, rd_val);
    check("rx_valid cleared by STATUS write", rd_val[1], 1'b0);

    configure_mode(1'b0, 1'b0, 2'd0, 1'b0);
    repeat (3) @(posedge clk);
    slv_preload[0] = 8'hDD;
    configure_mode(1'b0, 1'b0, 2'd0, 1'b1);
    repeat (3) @(posedge clk);
    spi_transfer(8'hAA);
    axi_read(REG_RXDATA, rd_val);
    axi_read(REG_STATUS, rd_val);
    check("rx_valid sticky after RXDATA read", rd_val[1], 1'b1);

    spi_transfer(8'h55);
    axi_read(REG_STATUS, rd_val);
    check("rx_valid remains after 2nd xfer", rd_val[1], 1'b1);

    axi_write(REG_STATUS, 32'h0000_0000);

    $display("");

    // ══════════════════════════════════════════════════════════════
    // TEST GRUBU 9: Interrupt Doğrulama (5 test)
    // ══════════════════════════════════════════════════════════════
    $display("── TEST GRUBU 9: Interrupt Dogrulama ─────────────────");

    configure_mode(1'b0, 1'b0, 2'd0, 1'b1);
    axi_write(REG_STATUS, 32'h0000_0000);
    repeat (3) @(posedge clk);
    check("IRQ: ie=0, rx_valid=0 -> 0", {31'd0, spi_irq}, 32'h0000_0000);

    slv_preload[0] = 8'hEE;
    spi_transfer(8'h77);
    repeat (3) @(posedge clk);
    check("IRQ: ie=0, rx_valid=1 -> 0", {31'd0, spi_irq}, 32'h0000_0000);

    axi_write(REG_CTRL, 32'h0000_0049);
    repeat (3) @(posedge clk);
    check("IRQ: ie=1, rx_valid=1 -> 1", {31'd0, spi_irq}, 32'h0000_0001);

    axi_write(REG_STATUS, 32'h0000_0000);
    repeat (3) @(posedge clk);
    check("IRQ: cleared after rx_valid clear", {31'd0, spi_irq}, 32'h0000_0000);

    slv_preload[0] = 8'hFF;
    spi_transfer(8'h11);
    repeat (3) @(posedge clk);
    check("IRQ: ie=1 + new xfer -> 1", {31'd0, spi_irq}, 32'h0000_0001);
    axi_write(REG_CTRL, 32'h0000_0041);
    repeat (3) @(posedge clk);
    check("IRQ: ie=0 disables irq", {31'd0, spi_irq}, 32'h0000_0000);

    axi_write(REG_STATUS, 32'h0000_0000);

    $display("");

    // ══════════════════════════════════════════════════════════════
    // TEST GRUBU 10: Chip Select Kontrol — 4 Slave (6 test)
    // ══════════════════════════════════════════════════════════════
    $display("── TEST GRUBU 10: Chip Select Kontrol ─────────────────");
    $display("  AD Spec: Ayri CS hatlari, active-low, regular mode");

    configure_mode(1'b0, 1'b0, 2'd0, 1'b1);
    repeat (3) @(posedge clk);
    check("CS0 assert: ss[0]=0", {31'd0, spi_ss[0]}, 32'h0000_0000);

    configure_mode(1'b0, 1'b0, 2'd1, 1'b1);
    repeat (3) @(posedge clk);
    check("CS1 assert: ss[1]=0", {31'd0, spi_ss[1]}, 32'h0000_0000);

    configure_mode(1'b0, 1'b0, 2'd2, 1'b1);
    repeat (3) @(posedge clk);
    check("CS2 assert: ss[2]=0", {31'd0, spi_ss[2]}, 32'h0000_0000);

    configure_mode(1'b0, 1'b0, 2'd3, 1'b1);
    repeat (3) @(posedge clk);
    check("CS3 assert: ss[3]=0", {31'd0, spi_ss[3]}, 32'h0000_0000);

    configure_mode(1'b0, 1'b0, 2'd0, 1'b0);
    repeat (3) @(posedge clk);
    check("CS deassert: all ss=1", {28'd0, spi_ss}, 32'h0000_000F);

    slv_preload[1] = 8'hB1;
    test_full_duplex("CS1 transfer", 1'b0, 1'b0, 2'd1, 8'h42, 8'hB1);

    $display("");

    // ══════════════════════════════════════════════════════════════
    // TEST GRUBU 11: Farklı CLK_DIV (3 test)
    // ══════════════════════════════════════════════════════════════
    $display("── TEST GRUBU 11: Farkli CLK_DIV ──────────────────────");

    axi_write(REG_CLK_DIV, 32'h0000_0007);
    test_full_duplex("CLK_DIV=7 xfer", 1'b0, 1'b0, 2'd0, 8'h17, 8'h71);

    axi_write(REG_CLK_DIV, 32'h0000_000F);
    test_full_duplex("CLK_DIV=15 xfer", 1'b0, 1'b0, 2'd0, 8'h0F, 8'hF0);

    axi_write(REG_CLK_DIV, {24'd0, SIM_CLK_DIV[7:0]});
    test_full_duplex("CLK_DIV=4 restore", 1'b0, 1'b0, 2'd0, 8'h44, 8'h44);

    $display("");

    // ══════════════════════════════════════════════════════════════
    // TEST GRUBU 12: Enable Kontrolü (3 test)
    // ══════════════════════════════════════════════════════════════
    $display("── TEST GRUBU 12: Enable Kontrolu ─────────────────────");

    axi_write(REG_CTRL, 32'h0000_0000);
    axi_read(REG_STATUS, rd_val);
    check("en=0: ready=0", rd_val[2], 1'b0);

    check("en=0: all ss=1", {28'd0, spi_ss}, 32'h0000_000F);

    configure_mode(1'b0, 1'b0, 2'd0, 1'b1);
    axi_read(REG_STATUS, rd_val);
    check("en=1: ready=1", rd_val[2], 1'b1);

    $display("");

    // ══════════════════════════════════════════════════════════════
    // TEST GRUBU 13: Busy Bayrağı (3 test)
    // ══════════════════════════════════════════════════════════════
    $display("── TEST GRUBU 13: Busy Bayragi ────────────────────────");

    axi_write(REG_STATUS, 32'h0000_0000);
    axi_write(REG_CLK_DIV, 32'h0000_000A);

    axi_write(REG_TXDATA, 32'h0000_00EE);
    axi_write(REG_CMD, 32'h0000_0001);
    axi_read(REG_STATUS, rd_val);
    check("busy=1 during transfer", rd_val[0], 1'b1);

    begin
      logic [31:0] st;
      int cnt;
      cnt = 0;
      do begin
        repeat (5) @(posedge clk);
        axi_read(REG_STATUS, st);
        cnt++;
      end while (st[0] && cnt < 500);
    end
    axi_read(REG_STATUS, rd_val);
    check("busy=0 after transfer", rd_val[0], 1'b0);

    check("ready=1 after transfer", rd_val[2], 1'b1);

    axi_write(REG_CLK_DIV, {24'd0, SIM_CLK_DIV[7:0]});

    $display("");

    // ══════════════════════════════════════════════════════════════
    // Sonuç Raporu
    // ══════════════════════════════════════════════════════════════
    $display("================================================================");
    $display(" SPI Fonksiyon Testi TAMAMLANDI");
    $display(" Toplam: %0d  |  PASS: %0d  |  FAIL: %0d", test_num, pass_cnt, fail_cnt);
    $display("================================================================");

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
    #5_000_000;
    $fatal(1, "[WATCHDOG] Zaman asimi — test 5ms icinde bitmedi!");
  end

  // ════════════════════════════════════════════════
  // VCD dump
  // ════════════════════════════════════════════════
  initial begin
    $dumpfile("tb_spi.vcd");
    $dumpvars(0, tb_spi);
  end

endmodule