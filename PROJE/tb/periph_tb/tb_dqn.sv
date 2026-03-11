// filepath: tb/periph_tb/tb_dqn.sv
// DQN Inference Accelerator — Birim Testi
// Dogrudan AXI Master IF uzerinden DQN accelerator'a erisim testi.
//
// Test Gruplari:
//   1. Register erisim testi (VERSION, CTRL, STATUS, STATE readback)
//   2. Agirlik yukleme ve readback
//   3. Bilinen degerlerle inference testi (identity-like weights)
//   4. LeakyReLU dogrulama (negatif giris)
//   5. Argmax dogrulama
//   6. Soft reset testi
//   7. Arka arkaya inference testi
`timescale 1ns / 1ps

module tb_dqn;
  import axi_pkg::*;

  // ════════════════════════════════════════════════
  // Clock & Reset
  // ════════════════════════════════════════════════
  logic clk;
  logic rstn;

  initial begin clk = 0; forever #5 clk = ~clk; end  // 10ns period = 100 MHz

  // ════════════════════════════════════════════════
  // DQN Register adresleri
  // ════════════════════════════════════════════════
  localparam logic [31:0] DQN_BASE     = 32'h4000_2000;
  localparam logic [31:0] DQN_CTRL     = DQN_BASE + 32'h00;
  localparam logic [31:0] DQN_STATUS   = DQN_BASE + 32'h04;
  localparam logic [31:0] DQN_STATE_0  = DQN_BASE + 32'h08;
  localparam logic [31:0] DQN_STATE_1  = DQN_BASE + 32'h0C;
  localparam logic [31:0] DQN_STATE_2  = DQN_BASE + 32'h10;
  localparam logic [31:0] DQN_STATE_3  = DQN_BASE + 32'h14;
  localparam logic [31:0] DQN_QVAL_0   = DQN_BASE + 32'h18;
  localparam logic [31:0] DQN_QVAL_1   = DQN_BASE + 32'h1C;
  localparam logic [31:0] DQN_QVAL_2   = DQN_BASE + 32'h20;
  localparam logic [31:0] DQN_QVAL_3   = DQN_BASE + 32'h24;
  localparam logic [31:0] DQN_QVAL_MAX = DQN_BASE + 32'h28;
  localparam logic [31:0] DQN_WT_ADDR  = DQN_BASE + 32'h2C;
  localparam logic [31:0] DQN_WT_DATA  = DQN_BASE + 32'h30;
  localparam logic [31:0] DQN_CYCLE_CNT= DQN_BASE + 32'h34;
  localparam logic [31:0] DQN_VERSION  = DQN_BASE + 32'h38;

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
  // AXI Master <-> Interconnect sinyalleri
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
  // Interconnect <-> Slave sinyalleri
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
  // DUT: DQN Accelerator (Slave 5)
  // ════════════════════════════════════════════════
  dqn_accelerator u_dqn_accel (
    .clk_i            (clk),
    .rstn_i           (rstn),
    .s_axi_awaddr_i   (slv_awaddr  [SLV_DQN]),
    .s_axi_awprot_i   (slv_awprot  [SLV_DQN]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_DQN]),
    .s_axi_awready_o  (slv_awready [SLV_DQN]),
    .s_axi_wdata_i    (slv_wdata   [SLV_DQN]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_DQN]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_DQN]),
    .s_axi_wready_o   (slv_wready  [SLV_DQN]),
    .s_axi_bresp_o    (slv_bresp   [SLV_DQN]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_DQN]),
    .s_axi_bready_i   (slv_bready  [SLV_DQN]),
    .s_axi_araddr_i   (slv_araddr  [SLV_DQN]),
    .s_axi_arprot_i   (slv_arprot  [SLV_DQN]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_DQN]),
    .s_axi_arready_o  (slv_arready [SLV_DQN]),
    .s_axi_rdata_o    (slv_rdata   [SLV_DQN]),
    .s_axi_rresp_o    (slv_rresp   [SLV_DQN]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_DQN]),
    .s_axi_rready_i   (slv_rready  [SLV_DQN])
  );

  // ════════════════════════════════════════════════
  // Kullanilmayan slave portlarini baglama
  // (Interconnect NUM_SLAVES=6 bekliyor, sadece SLV_DQN bagli)
  // ════════════════════════════════════════════════
  generate
    for (genvar s = 0; s < NUM_SLAVES; s++) begin : gen_unused_slaves
      if (s != SLV_DQN) begin
        assign slv_awready[s] = 1'b1;
        assign slv_wready[s]  = 1'b1;
        assign slv_bresp[s]   = 2'b00;
        assign slv_bvalid[s]  = 1'b0;
        assign slv_arready[s] = 1'b1;
        assign slv_rdata[s]   = 32'hDEAD_BEEF;
        assign slv_rresp[s]   = 2'b00;
        assign slv_rvalid[s]  = 1'b0;
      end
    end
  endgenerate

  // ════════════════════════════════════════════════
  // AXI Transaction Task'lari
  // ════════════════════════════════════════════════
  task automatic axi_write(
    input logic [31:0] addr,
    input logic [31:0] data,
    input logic [1:0]  size
  );
    while (!drv_ready) @(posedge clk);
    @(negedge clk);
    drv_mem_write    = 1'b1;
    drv_mem_read     = 1'b0;
    drv_addr         = addr;
    drv_wdata        = data;
    drv_mem_size     = size;
    drv_mem_unsigned = 1'b0;
    @(negedge clk);
    drv_mem_write = 1'b0;
    while (!drv_ready) @(posedge clk);
  endtask

  task automatic axi_read(
    input  logic [31:0] addr,
    input  logic [1:0]  size,
    output logic [31:0] rdata
  );
    while (!drv_ready) @(posedge clk);
    @(negedge clk);
    drv_mem_read     = 1'b1;
    drv_mem_write    = 1'b0;
    drv_addr         = addr;
    drv_mem_size     = size;
    drv_mem_unsigned = 1'b1;
    @(negedge clk);
    drv_mem_read = 1'b0;
    while (!drv_ready) @(posedge clk);
    rdata = drv_rdata;
  endtask

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
  // Agirlik yukleme helper task'i
  // 148 agirlik auto-increment ile yukler
  // ════════════════════════════════════════════════
  task automatic load_weights(
    input logic signed [15:0] weights [0:147]
  );
    // wt_load_mode acik, enable acik
    axi_write(DQN_CTRL, 32'h0000_0009, 2'b10);  // enable=1, wt_load_mode=1
    // WT_ADDR = 0
    axi_write(DQN_WT_ADDR, 32'h0000_0000, 2'b10);
    // 148 agirligi yaz
    for (int i = 0; i < 148; i++) begin
      axi_write(DQN_WT_DATA, {{16{weights[i][15]}}, weights[i]}, 2'b10);
    end
    // wt_load_mode kapat
    axi_write(DQN_CTRL, 32'h0000_0001, 2'b10);  // enable=1, wt_load_mode=0
  endtask

  // ════════════════════════════════════════════════
  // Inference tetikleme ve bekleme
  // ════════════════════════════════════════════════
  task automatic run_inference();
    logic [31:0] status;
    // start pulse
    axi_write(DQN_CTRL, 32'h0000_0003, 2'b10);  // enable=1, start=1

    // done bekle (polling)
    status = 32'h0;
    while (!(status & 32'h2)) begin
      axi_read(DQN_STATUS, 2'b10, status);
    end
  endtask

  // ════════════════════════════════════════════════
  // Ana Test Sekansi
  // ════════════════════════════════════════════════
  logic [31:0] rd_val;

  // Test agirliklari: basit identity-like setup
  // FC1: 4x16 — sadece ilk 4 noron icin diagonal identity (0.5),
  //             geri kalan 12 noron sifir agirlik
  // FC1_bias: hep sifir
  // FC2: 16x4 — sadece ilk 4 hidden'dan okuyarak diagonal identity (0.5)
  // FC2_bias: hep sifir
  //
  // Boylece: state[i] -> hidden[i] = LeakyReLU(state[i]*0.5) -> q_val[i] = hidden[i]*0.5
  // Ornek: state = [0.5, 0.25, 0.75, -0.5]
  //   hidden[0] = ReLU(0.5*0.5)     = 0.25
  //   hidden[1] = ReLU(0.25*0.5)    = 0.125
  //   hidden[2] = ReLU(0.75*0.5)    = 0.375
  //   hidden[3] = ReLU(-0.5*0.5)    = ReLU(-0.25) = -0.25*0.01 = -0.0025
  //   hidden[4..15] = 0 (sifir agirlik)
  //   q_val[0] = hidden[0]*0.5 = 0.125
  //   q_val[1] = hidden[1]*0.5 = 0.0625
  //   q_val[2] = hidden[2]*0.5 = 0.1875
  //   q_val[3] = hidden[3]*0.5 = -0.00125
  //
  // Q1.15 degerleri:
  //   0.5  = 16'h4000
  //   0.25 = 16'h2000
  //   0.75 = 16'h6000
  //  -0.5  = 16'hC000

  logic signed [15:0] test_weights [0:147];

  initial begin
    $display("════════════════════════════════════════════════");
    $display("  DQN Inference Accelerator — Birim Testi");
    $display("════════════════════════════════════════════════");

    // Varsayilan sinyal degerleri
    drv_mem_read     = 1'b0;
    drv_mem_write    = 1'b0;
    drv_mem_size     = 2'b10;
    drv_mem_unsigned = 1'b0;
    drv_addr         = '0;
    drv_wdata        = '0;

    // Agirlik dizisini sifirla
    for (int i = 0; i < 148; i++) test_weights[i] = 16'sh0000;

    // FC1 identity weights: fc1_w[i][i] = 0.5 (i=0..3)
    // addr = input_idx * 16 + output_idx
    test_weights[0*16 + 0] = 16'sh4000;  // fc1_w[0][0] = 0.5
    test_weights[1*16 + 1] = 16'sh4000;  // fc1_w[1][1] = 0.5
    test_weights[2*16 + 2] = 16'sh4000;  // fc1_w[2][2] = 0.5
    test_weights[3*16 + 3] = 16'sh4000;  // fc1_w[3][3] = 0.5
    // FC1 biases (64..79): hep sifir (zaten)

    // FC2 identity weights: fc2_w[i][i] = 0.5 (i=0..3)
    // addr = 80 + input_idx * 4 + output_idx
    test_weights[80 + 0*4 + 0] = 16'sh4000;  // fc2_w[0][0] = 0.5
    test_weights[80 + 1*4 + 1] = 16'sh4000;  // fc2_w[1][1] = 0.5
    test_weights[80 + 2*4 + 2] = 16'sh4000;  // fc2_w[2][2] = 0.5
    test_weights[80 + 3*4 + 3] = 16'sh4000;  // fc2_w[3][3] = 0.5
    // FC2 biases (144..147): hep sifir (zaten)

    // Reset
    rstn = 1'b0;
    repeat(10) @(posedge clk);
    rstn = 1'b1;
    repeat(5) @(posedge clk);

    // ──────────────────────────────────────────────
    // TEST GRUBU 1: Register Erisim
    // ──────────────────────────────────────────────
    $display("\n── TEST GRUBU 1: Register Erisim ──────────────────");

    // 1.1: VERSION register oku
    axi_read(DQN_VERSION, 2'b10, rd_val);
    check("VERSION", rd_val, 32'h44514E01);

    // 1.2: STATUS baslangic (busy=0, done=0, wt_loaded=0)
    axi_read(DQN_STATUS, 2'b10, rd_val);
    check("STATUS reset", rd_val[2:0], 3'b000);

    // 1.3: CTRL yaz ve oku
    axi_write(DQN_CTRL, 32'h0000_0001, 2'b10);  // enable=1
    axi_read(DQN_CTRL, 2'b10, rd_val);
    check("CTRL enable", rd_val[0], 1'b1);

    // 1.4: STATE register yaz ve oku
    axi_write(DQN_STATE_0, 32'h0000_4000, 2'b10);  // 0.5 Q1.15
    axi_read(DQN_STATE_0, 2'b10, rd_val);
    check("STATE_0 readback", rd_val[15:0], 16'h4000);

    axi_write(DQN_STATE_1, 32'h0000_2000, 2'b10);  // 0.25
    axi_read(DQN_STATE_1, 2'b10, rd_val);
    check("STATE_1 readback", rd_val[15:0], 16'h2000);

    // 1.5: Bilinmeyen adres -> DEAD_BEEF
    axi_read(DQN_BASE + 32'h3C, 2'b10, rd_val);
    check("Unknown addr", rd_val, 32'hDEAD_BEEF);

    // ──────────────────────────────────────────────
    // TEST GRUBU 2: Agirlik Yukleme ve Readback
    // ──────────────────────────────────────────────
    $display("\n── TEST GRUBU 2: Agirlik Yukleme ──────────────────");

    // 2.1: Agirliklari yukle
    load_weights(test_weights);

    // 2.2: wt_loaded flag kontrolu
    axi_read(DQN_STATUS, 2'b10, rd_val);
    check("wt_loaded flag", rd_val[2], 1'b1);

    // 2.3: Birinci agirligi geri oku (fc1_w[0][0] = 0.5)
    axi_write(DQN_WT_ADDR, 32'h0000_0000, 2'b10);
    axi_read(DQN_WT_DATA, 2'b10, rd_val);
    check("WT readback fc1_w[0][0]", rd_val[15:0], 16'h4000);

    // 2.4: Diagonal agirlik oku (fc1_w[1][1], addr=17)
    axi_write(DQN_WT_ADDR, 32'h0000_0011, 2'b10);  // addr=17
    axi_read(DQN_WT_DATA, 2'b10, rd_val);
    check("WT readback fc1_w[1][1]", rd_val[15:0], 16'h4000);

    // 2.5: Sifir agirlik oku (fc1_w[0][1], addr=1)
    axi_write(DQN_WT_ADDR, 32'h0000_0001, 2'b10);
    axi_read(DQN_WT_DATA, 2'b10, rd_val);
    check("WT readback zero weight", rd_val[15:0], 16'h0000);

    // 2.6: FC2 agirligi oku (fc2_w[0][0], addr=80)
    axi_write(DQN_WT_ADDR, 32'h0000_0050, 2'b10);  // 80 = 0x50
    axi_read(DQN_WT_DATA, 2'b10, rd_val);
    check("WT readback fc2_w[0][0]", rd_val[15:0], 16'h4000);

    // ──────────────────────────────────────────────
    // TEST GRUBU 3: Inference — Positif Girisler
    // ──────────────────────────────────────────────
    $display("\n── TEST GRUBU 3: Inference (Positif) ──────────────");

    // State: [0.5, 0.25, 0.75, 0.125]
    // Q1.15: 0.5=0x4000, 0.25=0x2000, 0.75=0x6000, 0.125=0x1000
    axi_write(DQN_STATE_0, 32'h0000_4000, 2'b10);
    axi_write(DQN_STATE_1, 32'h0000_2000, 2'b10);
    axi_write(DQN_STATE_2, 32'h0000_6000, 2'b10);
    axi_write(DQN_STATE_3, 32'h0000_1000, 2'b10);

    // enable olmali
    axi_write(DQN_CTRL, 32'h0000_0001, 2'b10);

    // Inference calistir
    run_inference();

    // Q-value'lari oku
    // Beklenen (identity-like weights ile):
    //   q_val[0] = state[0]*0.5*0.5 = 0.5*0.25 = 0.125 = 0x1000
    //   q_val[1] = state[1]*0.5*0.5 = 0.25*0.25 = 0.0625 = 0x0800
    //   q_val[2] = state[2]*0.5*0.5 = 0.75*0.25 = 0.1875 = 0x1800
    //   q_val[3] = state[3]*0.5*0.5 = 0.125*0.25 = 0.03125 = 0x0400
    axi_read(DQN_QVAL_0, 2'b10, rd_val);
    check("QVAL_0 (0.125)", rd_val[15:0], 16'h1000);

    axi_read(DQN_QVAL_1, 2'b10, rd_val);
    check("QVAL_1 (0.0625)", rd_val[15:0], 16'h0800);

    axi_read(DQN_QVAL_2, 2'b10, rd_val);
    check("QVAL_2 (0.1875)", rd_val[15:0], 16'h1800);

    axi_read(DQN_QVAL_3, 2'b10, rd_val);
    check("QVAL_3 (0.03125)", rd_val[15:0], 16'h0400);

    // 3.5: Argmax kontrolu — q_val[2] en buyuk, argmax=2
    axi_read(DQN_STATUS, 2'b10, rd_val);
    check("argmax=2", rd_val[5:4], 2'd2);

    // 3.6: QVAL_MAX kontrolu
    axi_read(DQN_QVAL_MAX, 2'b10, rd_val);
    check("QVAL_MAX (0.1875)", rd_val[15:0], 16'h1800);

    // 3.7: Cycle count > 0
    axi_read(DQN_CYCLE_CNT, 2'b10, rd_val);
    check("CYCLE_CNT > 0", (rd_val > 0) ? 32'd1 : 32'd0, 32'd1);
    $display("  Inference cycle count = %0d", rd_val[15:0]);

    // ──────────────────────────────────────────────
    // TEST GRUBU 4: Inference — Negatif Giris (LeakyReLU)
    // ──────────────────────────────────────────────
    $display("\n── TEST GRUBU 4: LeakyReLU Dogrulama ──────────────");

    // State: [0.5, 0.25, 0.75, -0.5]
    // -0.5 Q1.15 = 0xC000
    axi_write(DQN_STATE_3, 32'h0000_C000, 2'b10);

    run_inference();

    // q_val[3]: hidden[3] = LeakyReLU(-0.5*0.5) = LeakyReLU(-0.25) = -0.25*0.01 = -0.0025
    //   -0.25 Q1.15 = 0xE000
    //   -0.25 * 0.01 (=0x0148): (-0x2000 * 0x0148) >> 15
    //   = -(0x2000 * 0x0148) >> 15 = -(0x290000) >> 15 = -(0x52) = -82 yaklasik
    //   Sonra: q_val[3] = hidden[3] * 0.5 => daha da kucuk
    // Negatif degerin kesin hesabi fixed-point truncation'a bagli
    // Ana test: q_val[3] < 0 olmali
    axi_read(DQN_QVAL_3, 2'b10, rd_val);
    check("QVAL_3 negatif", rd_val[15], 1'b1);  // isaret biti 1 = negatif

    // Diger Q-value'lar ayni kalmali
    axi_read(DQN_QVAL_0, 2'b10, rd_val);
    check("QVAL_0 ayni (0.125)", rd_val[15:0], 16'h1000);

    // Argmax hala 2 olmali (q_val[2] = 0.1875 en buyuk)
    axi_read(DQN_STATUS, 2'b10, rd_val);
    check("argmax hala 2", rd_val[5:4], 2'd2);

    // ──────────────────────────────────────────────
    // TEST GRUBU 5: Soft Reset
    // ──────────────────────────────────────────────
    $display("\n── TEST GRUBU 5: Soft Reset ──────────────────────");

    // Soft reset: done temizlenmeli
    axi_write(DQN_CTRL, 32'h0000_0005, 2'b10);  // enable=1, soft_reset=1

    repeat(5) @(posedge clk);

    // busy ve done 0 olmali
    axi_read(DQN_STATUS, 2'b10, rd_val);
    check("busy after reset", rd_val[0], 1'b0);

    // ──────────────────────────────────────────────
    // TEST GRUBU 6: Arka Arkaya Inference
    // ──────────────────────────────────────────────
    $display("\n── TEST GRUBU 6: Arka Arkaya Inference ────────────");

    // Ilk inference: state = [0.5, 0.5, 0.5, 0.5]
    axi_write(DQN_STATE_0, 32'h0000_4000, 2'b10);
    axi_write(DQN_STATE_1, 32'h0000_4000, 2'b10);
    axi_write(DQN_STATE_2, 32'h0000_4000, 2'b10);
    axi_write(DQN_STATE_3, 32'h0000_4000, 2'b10);
    run_inference();

    // Tum Q-value'lar esit olmali: 0.5*0.5*0.5 = 0.125 = 0x1000
    axi_read(DQN_QVAL_0, 2'b10, rd_val);
    check("B2B QVAL_0 (0.125)", rd_val[15:0], 16'h1000);

    axi_read(DQN_QVAL_1, 2'b10, rd_val);
    check("B2B QVAL_1 (0.125)", rd_val[15:0], 16'h1000);

    // Ikinci inference: farkli state = [0.25, 0.75, 0.125, 0.5]
    axi_write(DQN_STATE_0, 32'h0000_2000, 2'b10);
    axi_write(DQN_STATE_1, 32'h0000_6000, 2'b10);
    axi_write(DQN_STATE_2, 32'h0000_1000, 2'b10);
    axi_write(DQN_STATE_3, 32'h0000_4000, 2'b10);
    run_inference();

    // q_val[0] = 0.25*0.25 = 0.0625 = 0x0800
    axi_read(DQN_QVAL_0, 2'b10, rd_val);
    check("B2B-2 QVAL_0 (0.0625)", rd_val[15:0], 16'h0800);

    // q_val[1] = 0.75*0.25 = 0.1875 = 0x1800
    axi_read(DQN_QVAL_1, 2'b10, rd_val);
    check("B2B-2 QVAL_1 (0.1875)", rd_val[15:0], 16'h1800);

    // Argmax = 1 (q_val[1] = 0.1875 en buyuk)
    axi_read(DQN_STATUS, 2'b10, rd_val);
    check("B2B-2 argmax=1", rd_val[5:4], 2'd1);

    // ──────────────────────────────────────────────
    // SONUC
    // ──────────────────────────────────────────────
    $display("\n════════════════════════════════════════════════");
    $display("  DQN Birim Testi Sonucu: %0d/%0d PASS", pass_cnt, test_num);
    if (fail_cnt > 0)
      $display("  UYARI: %0d test BASARISIZ!", fail_cnt);
    else
      $display("  Tum testler BASARILI");
    $display("════════════════════════════════════════════════");
    $finish;
  end

  // ════════════════════════════════════════════════
  // Timeout korumasi
  // ════════════════════════════════════════════════
  initial begin
    #500_000;
    $display("[TIMEOUT] Simülasyon zaman asimi!");
    $finish;
  end

endmodule
