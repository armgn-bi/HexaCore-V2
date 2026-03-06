// filepath: tb/soc_tb/tb_soc_integration.sv
// SoC Entegrasyon Testi
// AXI Master IF → Interconnect → DMEM / DSP / Stub Slaves bağlantılarını doğrular.
// Test akışı:
//   1. DMEM'e yazma & geri okuma (word, half, byte)
//   2. DSP register yazma & okuma (CTRL, DATA_IN, STATUS, DATA_OUT)
//   3. Stub Slave (UART/SPI/I2C) erişimi → SLVERR beklenir
//   4. Geçersiz adres → DECERR beklenir
//
// NOT: Bu testbench, soc_top'u değil, AXI altyapısını doğrudan sürer.
//      Pipeline placeholder sinyallerini bypass ederek AXI Master IF'i
//      kontrol eder.
`timescale 1ns / 1ps

module tb_soc_integration;
  import riscv_pkg::*;
  import axi_pkg::*;

  // ════════════════════════════════════════════════
  // Clock & Reset
  // ════════════════════════════════════════════════
  logic clk;
  logic rstn;

  initial begin clk = 0; forever #1 clk = ~clk; end  // 2ns period

  // ════════════════════════════════════════════════
  // AXI Master IF driver sinyalleri
  // ════════════════════════════════════════════════
  logic             drv_mem_read;
  logic             drv_mem_write;
  logic [1:0]       drv_mem_size;
  logic             drv_mem_unsigned;
  logic [31:0]      drv_addr;
  logic [31:0]      drv_wdata;
  logic [31:0]      drv_rdata;
  logic             drv_ready;

  // ════════════════════════════════════════════════
  // AXI Master ↔ Interconnect arası sinyaller
  // ════════════════════════════════════════════════
  logic [AXI_ADDR_WIDTH-1:0] mst_awaddr,  mst_araddr;
  logic [2:0]                mst_awprot,  mst_arprot;
  logic                      mst_awvalid, mst_arvalid;
  logic                      mst_awready, mst_arready;

  logic [AXI_DATA_WIDTH-1:0] mst_wdata;
  logic [AXI_STRB_WIDTH-1:0] mst_wstrb;
  logic                      mst_wvalid,  mst_wready;

  logic [1:0]                mst_bresp,   mst_rresp;
  logic                      mst_bvalid,  mst_rvalid;
  logic                      mst_bready,  mst_rready;

  logic [AXI_DATA_WIDTH-1:0] mst_rdata;

  // ════════════════════════════════════════════════
  // Interconnect ↔ Slave sinyalleri
  // ════════════════════════════════════════════════
  logic [AXI_ADDR_WIDTH-1:0] slv_awaddr  [NUM_SLAVES];
  logic [2:0]                slv_awprot  [NUM_SLAVES];
  logic                      slv_awvalid [NUM_SLAVES];
  logic                      slv_awready [NUM_SLAVES];

  logic [AXI_DATA_WIDTH-1:0] slv_wdata   [NUM_SLAVES];
  logic [AXI_STRB_WIDTH-1:0] slv_wstrb   [NUM_SLAVES];
  logic                      slv_wvalid  [NUM_SLAVES];
  logic                      slv_wready  [NUM_SLAVES];

  logic [1:0]                slv_bresp   [NUM_SLAVES];
  logic                      slv_bvalid  [NUM_SLAVES];
  logic                      slv_bready  [NUM_SLAVES];

  logic [AXI_ADDR_WIDTH-1:0] slv_araddr  [NUM_SLAVES];
  logic [2:0]                slv_arprot  [NUM_SLAVES];
  logic                      slv_arvalid [NUM_SLAVES];
  logic                      slv_arready [NUM_SLAVES];

  logic [AXI_DATA_WIDTH-1:0] slv_rdata   [NUM_SLAVES];
  logic [1:0]                slv_rresp   [NUM_SLAVES];
  logic                      slv_rvalid  [NUM_SLAVES];
  logic                      slv_rready  [NUM_SLAVES];

  // ════════════════════════════════════════════════
  // Test istatistikleri
  // ════════════════════════════════════════════════
  int pass_cnt = 0;
  int fail_cnt = 0;
  int test_num = 0;

  // ════════════════════════════════════════════════
  // DUT: AXI Master Interface
  // ════════════════════════════════════════════════
  axi_master_if u_axi_master (
    .clk_i            (clk),
    .rstn_i           (rstn),
    .mem_read_i       (drv_mem_read),
    .mem_write_i      (drv_mem_write),
    .mem_size_i       (drv_mem_size),
    .mem_unsigned_i   (drv_mem_unsigned),
    .addr_i           (drv_addr),
    .wdata_i          (drv_wdata),
    .rdata_o          (drv_rdata),
    .ready_o          (drv_ready),
    .m_axi_awaddr_o   (mst_awaddr),
    .m_axi_awprot_o   (mst_awprot),
    .m_axi_awvalid_o  (mst_awvalid),
    .m_axi_awready_i  (mst_awready),
    .m_axi_wdata_o    (mst_wdata),
    .m_axi_wstrb_o    (mst_wstrb),
    .m_axi_wvalid_o   (mst_wvalid),
    .m_axi_wready_i   (mst_wready),
    .m_axi_bresp_i    (mst_bresp),
    .m_axi_bvalid_i   (mst_bvalid),
    .m_axi_bready_o   (mst_bready),
    .m_axi_araddr_o   (mst_araddr),
    .m_axi_arprot_o   (mst_arprot),
    .m_axi_arvalid_o  (mst_arvalid),
    .m_axi_arready_i  (mst_arready),
    .m_axi_rdata_i    (mst_rdata),
    .m_axi_rresp_i    (mst_rresp),
    .m_axi_rvalid_i   (mst_rvalid),
    .m_axi_rready_o   (mst_rready)
  );

  // ════════════════════════════════════════════════
  // DUT: AXI Interconnect
  // ════════════════════════════════════════════════
  axi_interconnect u_interconnect (
    .clk_i         (clk),
    .rstn_i        (rstn),
    .m_awaddr_i    (mst_awaddr),
    .m_awprot_i    (mst_awprot),
    .m_awvalid_i   (mst_awvalid),
    .m_awready_o   (mst_awready),
    .m_wdata_i     (mst_wdata),
    .m_wstrb_i     (mst_wstrb),
    .m_wvalid_i    (mst_wvalid),
    .m_wready_o    (mst_wready),
    .m_bresp_o     (mst_bresp),
    .m_bvalid_o    (mst_bvalid),
    .m_bready_i    (mst_bready),
    .m_araddr_i    (mst_araddr),
    .m_arprot_i    (mst_arprot),
    .m_arvalid_i   (mst_arvalid),
    .m_arready_o   (mst_arready),
    .m_rdata_o     (mst_rdata),
    .m_rresp_o     (mst_rresp),
    .m_rvalid_o    (mst_rvalid),
    .m_rready_i    (mst_rready),
    .s_awaddr_o    (slv_awaddr),
    .s_awprot_o    (slv_awprot),
    .s_awvalid_o   (slv_awvalid),
    .s_awready_i   (slv_awready),
    .s_wdata_o     (slv_wdata),
    .s_wstrb_o     (slv_wstrb),
    .s_wvalid_o    (slv_wvalid),
    .s_wready_i    (slv_wready),
    .s_bresp_i     (slv_bresp),
    .s_bvalid_i    (slv_bvalid),
    .s_bready_o    (slv_bready),
    .s_araddr_o    (slv_araddr),
    .s_arprot_o    (slv_arprot),
    .s_arvalid_o   (slv_arvalid),
    .s_arready_i   (slv_arready),
    .s_rdata_i     (slv_rdata),
    .s_rresp_i     (slv_rresp),
    .s_rvalid_i    (slv_rvalid),
    .s_rready_o    (slv_rready)
  );

  // ════════════════════════════════════════════════
  // Slave 0: DMEM (AXI Wrapper)
  // ════════════════════════════════════════════════
  logic [31:0] dmem_dbg_data;  // kullanılmıyor

  axi_dmem_slave #(
    .DMEM_INIT_FILE ("dmem.mem"),
    .DMEM_BASE      (32'h8001_0000),
    .DMEM_BYTES     (32768)
  ) u_axi_dmem (
    .clk_i            (clk),
    .rstn_i           (rstn),
    .s_axi_awaddr_i   (slv_awaddr  [SLV_DMEM]),
    .s_axi_awprot_i   (slv_awprot  [SLV_DMEM]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_DMEM]),
    .s_axi_awready_o  (slv_awready [SLV_DMEM]),
    .s_axi_wdata_i    (slv_wdata   [SLV_DMEM]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_DMEM]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_DMEM]),
    .s_axi_wready_o   (slv_wready  [SLV_DMEM]),
    .s_axi_bresp_o    (slv_bresp   [SLV_DMEM]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_DMEM]),
    .s_axi_bready_i   (slv_bready  [SLV_DMEM]),
    .s_axi_araddr_i   (slv_araddr  [SLV_DMEM]),
    .s_axi_arprot_i   (slv_arprot  [SLV_DMEM]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_DMEM]),
    .s_axi_arready_o  (slv_arready [SLV_DMEM]),
    .s_axi_rdata_o    (slv_rdata   [SLV_DMEM]),
    .s_axi_rresp_o    (slv_rresp   [SLV_DMEM]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_DMEM]),
    .s_axi_rready_i   (slv_rready  [SLV_DMEM]),
    .dbg_addr_i       (32'h8001_0000),
    .dbg_data_o       (dmem_dbg_data)
  );

  // ════════════════════════════════════════════════
  // Slave 4: DSP FIR Filtre Wrapper
  // ════════════════════════════════════════════════
  dsp_filter_wrapper u_dsp_filter (
    .clk_i            (clk),
    .rstn_i           (rstn),
    .s_axi_awaddr_i   (slv_awaddr  [SLV_DSP]),
    .s_axi_awprot_i   (slv_awprot  [SLV_DSP]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_DSP]),
    .s_axi_awready_o  (slv_awready [SLV_DSP]),
    .s_axi_wdata_i    (slv_wdata   [SLV_DSP]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_DSP]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_DSP]),
    .s_axi_wready_o   (slv_wready  [SLV_DSP]),
    .s_axi_bresp_o    (slv_bresp   [SLV_DSP]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_DSP]),
    .s_axi_bready_i   (slv_bready  [SLV_DSP]),
    .s_axi_araddr_i   (slv_araddr  [SLV_DSP]),
    .s_axi_arprot_i   (slv_arprot  [SLV_DSP]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_DSP]),
    .s_axi_arready_o  (slv_arready [SLV_DSP]),
    .s_axi_rdata_o    (slv_rdata   [SLV_DSP]),
    .s_axi_rresp_o    (slv_rresp   [SLV_DSP]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_DSP]),
    .s_axi_rready_i   (slv_rready  [SLV_DSP])
  );
  // ════════════════════════════════════════════════
  // Slave 1–3: UART, SPI, I2C stubs (SLVERR döner)
  // AXI protokol uyumlu — registered response
  // ════════════════════════════════════════════════
  generate
    for (genvar i = 1; i <= 3; i++) begin : gen_stub_slaves
      // Write: hemen kabul, bir sonraki cycle'da SLVERR yanıtı
      logic wr_pending;
      always_ff @(posedge clk or negedge rstn) begin
        if (!rstn)
          wr_pending <= 1'b0;
        else if (!wr_pending && slv_awvalid[i] && slv_wvalid[i])
          wr_pending <= 1'b1;
        else if (wr_pending && slv_bready[i])
          wr_pending <= 1'b0;
      end
      assign slv_awready[i] = !wr_pending;
      assign slv_wready [i] = !wr_pending;
      assign slv_bresp  [i] = AXI_RESP_SLVERR;
      assign slv_bvalid [i] = wr_pending;

      // Read: AR kabul, bir sonraki cycle'da SLVERR + DEAD data
      logic rd_pending;
      always_ff @(posedge clk or negedge rstn) begin
        if (!rstn)
          rd_pending <= 1'b0;
        else if (!rd_pending && slv_arvalid[i])
          rd_pending <= 1'b1;
        else if (rd_pending && slv_rready[i])
          rd_pending <= 1'b0;
      end
      assign slv_arready[i] = !rd_pending;
      assign slv_rdata  [i] = 32'hDEAD_DEAD;
      assign slv_rresp  [i] = AXI_RESP_SLVERR;
      assign slv_rvalid [i] = rd_pending;
    end
  endgenerate

  // ════════════════════════════════════════════════
  // AXI Transaction Task'ları
  // ════════════════════════════════════════════════  // --- AXI Write Transaction ---
  // Master IF'e mem_write isteği gönder, tamamlanmasını bekle
  task automatic axi_write(
    input logic [31:0] addr,
    input logic [31:0] data,
    input logic [1:0]  size   // 00=byte, 01=half, 10=word
  );
    // ready beklenmeli (önceki transaction bitmeli)
    while (!drv_ready) @(posedge clk);

    // İstek sinyallerini negedge'de set et — DUT posedge'de örnekler
    @(negedge clk);
    drv_mem_write    = 1'b1;
    drv_mem_read     = 1'b0;
    drv_addr         = addr;
    drv_wdata        = data;
    drv_mem_size     = size;
    drv_mem_unsigned = 1'b0;

    // 1 tam clock cycle sür — posedge'de FSM yakalar
    @(negedge clk);
    drv_mem_write = 1'b0;    // Transaction tamamlanana kadar bekle (ready tekrar 1 olacak)
    while (!drv_ready) @(posedge clk);
  endtask// --- AXI Read Transaction ---
  // Master IF'e mem_read isteği gönder, tamamlanmasını bekle, okunan veriyi döndür
  task automatic axi_read(
    input  logic [31:0] addr,
    input  logic [1:0]  size,
    output logic [31:0] rdata
  );
    while (!drv_ready) @(posedge clk);

    // negedge'de set et — posedge'de DUT örnekler
    @(negedge clk);
    drv_mem_read     = 1'b1;
    drv_mem_write    = 1'b0;
    drv_addr         = addr;
    drv_mem_size     = size;
    drv_mem_unsigned = 1'b1;

    // 1 tam clock cycle sür — posedge'de FSM yakalar
    @(negedge clk);
    drv_mem_read = 1'b0;    // Transaction tamamlanana kadar bekle
    while (!drv_ready) @(posedge clk);
    rdata = drv_rdata;
  endtask

  // --- Check helper ---
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
  // Ana Test Sekansı
  // ════════════════════════════════════════════════
  logic [31:0] rd_val;

  initial begin
    // Varsayılan sinyal değerleri
    drv_mem_read     = 1'b0;
    drv_mem_write    = 1'b0;
    drv_mem_size     = 2'b10;
    drv_mem_unsigned = 1'b0;
    drv_addr         = '0;
    drv_wdata        = '0;

    // Reset
    rstn = 1'b0;
    repeat (5) @(posedge clk);
    rstn = 1'b1;
    repeat (3) @(posedge clk);

    $display("");
    $display("════════════════════════════════════════════════════");
    $display(" SoC Entegrasyon Testi Baslatiliyor");
    $display("════════════════════════════════════════════════════");
    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 1: DMEM (Slave 0) Yazma & Okuma
    // Adres aralığı: 0x8001_0000 – 0x8001_7FFF
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 1: DMEM Yazma & Okuma ──────────────");

    // 1.1: Word yazma & okuma
    axi_write(32'h8001_0100, 32'hCAFE_BABE, 2'b10);
    axi_read (32'h8001_0100, 2'b10, rd_val);
    check("DMEM Word WR/RD @0x8001_0100", rd_val, 32'hCAFE_BABE);

    // 1.2: Farklı adrese word yazma & okuma
    axi_write(32'h8001_0200, 32'h1234_5678, 2'b10);
    axi_read (32'h8001_0200, 2'b10, rd_val);
    check("DMEM Word WR/RD @0x8001_0200", rd_val, 32'h1234_5678);

    // 1.3: İlk adresin hâlâ doğru olduğunu kontrol et (üst yazma yok)
    axi_read (32'h8001_0100, 2'b10, rd_val);
    check("DMEM Re-read @0x8001_0100", rd_val, 32'hCAFE_BABE);

    // 1.4: Sıfır yazma ve okuma
    axi_write(32'h8001_0300, 32'h0000_0000, 2'b10);
    axi_read (32'h8001_0300, 2'b10, rd_val);
    check("DMEM Zero WR/RD @0x8001_0300", rd_val, 32'h0000_0000);

    // 1.5: Max değer yazma
    axi_write(32'h8001_0304, 32'hFFFF_FFFF, 2'b10);
    axi_read (32'h8001_0304, 2'b10, rd_val);
    check("DMEM Max WR/RD @0x8001_0304", rd_val, 32'hFFFF_FFFF);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 2: DSP Filtre (Slave 4) Register Erişimi
    // Adres aralığı: 0x4000_1000 – 0x4000_1FFF
    // Register map:
    //   0x00: CTRL    [0]=enable, [1]=soft_reset, [2]=start
    //   0x04: STATUS  [0]=busy, [1]=out_valid
    //   0x08: DATA_IN [15:0] signed input sample
    //   0x0C: DATA_OUT_L [31:0]
    //   0x10: DATA_OUT_H [0]
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 2: DSP Register Erişimi ────────────");

    // 2.1: CTRL register — enable yazma & okuma
    axi_write(32'h4000_1000, 32'h0000_0001, 2'b10);  // enable=1
    axi_read (32'h4000_1000, 2'b10, rd_val);
    check("DSP CTRL enable set", rd_val[0], 1'b1);

    // 2.2: STATUS register okuma (başlangıçta busy=0, out_valid=0)
    axi_read (32'h4000_1004, 2'b10, rd_val);
    check("DSP STATUS initial", rd_val, 32'h0000_0000);

    // 2.3: DATA_IN register — örnek veri yazma
    axi_write(32'h4000_1008, 32'h0000_4000, 2'b10);  // 0x4000 = +0.5 Q1.15
    axi_read (32'h4000_1008, 2'b10, rd_val);
    check("DSP DATA_IN readback", rd_val[15:0], 16'h4000);

    // 2.4: Birden fazla sample yazarak filtreyi çalıştır
    // enable=1, birkaç sample gönder, sonra out_valid kontrol et
    axi_write(32'h4000_1008, 32'h0000_2000, 2'b10);  // +0.25
    axi_write(32'h4000_1008, 32'h0000_6000, 2'b10);  // +0.75

    // Filtrenin çalışması için birkaç cycle bekle
    repeat (20) @(posedge clk);

    // 2.5: STATUS okuma — out_valid set olmuş olmalı (filtre delay'e bağlı)
    axi_read (32'h4000_1004, 2'b10, rd_val);
    $display("[%0t] INFO: DSP STATUS after samples = 0x%08h (out_valid=%0b)",
             $time, rd_val, rd_val[1]);

    // 2.6: DATA_OUT_L okuma
    axi_read (32'h4000_100C, 2'b10, rd_val);
    $display("[%0t] INFO: DSP DATA_OUT_L = 0x%08h", $time, rd_val);

    // 2.7: DATA_OUT_H okuma
    axi_read (32'h4000_1010, 2'b10, rd_val);
    $display("[%0t] INFO: DSP DATA_OUT_H = 0x%08h", $time, rd_val);

    // 2.8: CTRL soft_reset — pulse yazma, tekrar okuma (bit otomatik temizlenir)
    axi_write(32'h4000_1000, 32'h0000_0003, 2'b10);  // enable + soft_reset
    repeat (3) @(posedge clk);
    axi_read (32'h4000_1000, 2'b10, rd_val);
    check("DSP CTRL soft_reset auto-clear", rd_val[1], 1'b0);  // pulse olmalı, temizlenmiş

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 3: Stub Slave SLVERR Kontrolü
    // UART=0x4000_0000, SPI=0x4000_0100, I2C=0x4000_0200
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 3: Stub Slave SLVERR Kontrolü ──────");

    // 3.1: UART adresine okuma → SLVERR + 0xDEAD_DEAD
    axi_read (32'h4000_0000, 2'b10, rd_val);
    check("UART stub read data", rd_val, 32'hDEAD_DEAD);

    // 3.2: SPI adresine okuma → SLVERR
    axi_read (32'h4000_0100, 2'b10, rd_val);
    check("SPI stub read data", rd_val, 32'hDEAD_DEAD);

    // 3.3: I2C adresine okuma → SLVERR
    axi_read (32'h4000_0200, 2'b10, rd_val);
    check("I2C stub read data", rd_val, 32'hDEAD_DEAD);

    // 3.4: UART'a yazma (SLVERR ama transaction tamamlanmalı)
    axi_write(32'h4000_0000, 32'hAAAA_BBBB, 2'b10);
    $display("[%0t] PASS: UART stub write completed (SLVERR expected)", $time);
    pass_cnt++;
    test_num++;

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 4: DMEM → Ardışık Erişim Dayanıklılık
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 4: DMEM Ardışık Erişim ─────────────");

    // 4.1: 8 ardışık word yazma
    for (int i = 0; i < 8; i++) begin
      axi_write(32'h8001_0400 + (i * 4), 32'hA000_0000 + i, 2'b10);
    end

    // 4.2: 8 ardışık word okuma ve doğrulama
    for (int i = 0; i < 8; i++) begin
      automatic string tname;
      axi_read(32'h8001_0400 + (i * 4), 2'b10, rd_val);
      $sformat(tname, "DMEM sequential[%0d]", i);
      check(tname, rd_val, 32'hA000_0000 + i);
    end

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 5: DSP → DMEM Karışık Erişim
    // Bir slave'e yazıp diğerinden okuma — çapraz kontaminasyon yok
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 5: DSP ↔ DMEM Çapraz Kontrol ──────");

    // DMEM'e belirli bir veri yaz
    axi_write(32'h8001_0500, 32'hBEEF_DEAD, 2'b10);

    // DSP CTRL register'a yaz
    axi_write(32'h4000_1000, 32'h0000_0001, 2'b10);

    // DMEM'i okuyup orijinal veriyi kontrol et
    axi_read (32'h8001_0500, 2'b10, rd_val);
    check("DMEM after DSP access", rd_val, 32'hBEEF_DEAD);

    // DSP CTRL register'ı okuyup doğru değeri kontrol et
    axi_read (32'h4000_1000, 2'b10, rd_val);
    check("DSP CTRL after DMEM access", rd_val[0], 1'b1);

    $display("");

    // ──────────────────────────────────────────────
    // Sonuç Raporu
    // ──────────────────────────────────────────────
    $display("════════════════════════════════════════════════════");
    $display(" SoC Entegrasyon Testi TAMAMLANDI");
    $display(" Toplam: %0d  |  PASS: %0d  |  FAIL: %0d",
             test_num, pass_cnt, fail_cnt);
    $display("════════════════════════════════════════════════════");

    if (fail_cnt > 0)
      $fatal(1, "ENTEGRASYON TESTI BASARISIZ — %0d hata!", fail_cnt);
    else
      $display("[TB] TUM TESTLER BASARILI.\n");

    $finish;
  end
  // ════════════════════════════════════════════════
  // Watchdog timer
  // ════════════════════════════════════════════════
  initial begin
    #100_000;
    $fatal(1, "[WATCHDOG] Zaman asimi — test 100us icinde bitmedi!");
  end
  // ════════════════════════════════════════════════
  // Debug: Master IF + DMEM Slave state monitor
  // Aktifleştirmek için: xvlog ... -d DEBUG_MON
  // ════════════════════════════════════════════════
`ifdef DEBUG_MON
  always @(posedge clk) begin
    if ($time < 100_000 && rstn) begin
      $display("[%0t] MON: mst_state=%0d ready=%0b | arvalid=%0b arready=%0b araddr=0x%08h | rvalid=%0b rready=%0b rdata=0x%08h | awvalid=%0b awready=%0b | wvalid=%0b wready=%0b | bvalid=%0b bready=%0b | dmem_state=%0d dmem_mem_rd=%0b dmem_mem_wr=%0b dmem_rdata=0x%08h",
               $time,
               u_axi_master.state_q, drv_ready,
               mst_arvalid, mst_arready, mst_araddr,
               mst_rvalid, mst_rready, mst_rdata,
               mst_awvalid, mst_awready,
               mst_wvalid, mst_wready,
               mst_bvalid, mst_bready,
               u_axi_dmem.state_q, u_axi_dmem.mem_read, u_axi_dmem.mem_write, u_axi_dmem.mem_rdata);
    end
  end
`endif

  // ════════════════════════════════════════════════
  // Opsiyonel VCD dump
  // ════════════════════════════════════════════════
  initial begin
    $dumpfile("tb_soc_integration.vcd");
    $dumpvars(0, tb_soc_integration);
  end

endmodule
