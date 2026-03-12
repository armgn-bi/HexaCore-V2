// filepath: tb/periph_tb/tb_dqn_perf.sv
// DQN Performans Testi — CPU-only vs DQN+CPU Paralel Labirent Cozme
// Vivado XSIM uyumlu (AXI katmani ile tam donanim testi)
//
// 5 farkli karmasik labirent senaryosu (8x8 grid, duvarli):
//   State vektoru: Her yon icin cekicilik skoru (yon tercihi * duvar durumu)
//   state[0]=yukari, state[1]=asagi, state[2]=sol, state[3]=sag cekicilik
//   Aksiyon: 0=yukari, 1=asagi, 2=sol, 3=sag
//
// Olcumler:
//   1) CPU-only: Tum DQN inference hesaplamasi yazilimda yapilir (cycle sayimi)
//   2) DQN+CPU: DQN hizlandirici AXI uzerinden suruler, gercek cycle olculur
//   Her iki modda toplam cycle sayisi raporlanir ve karsilastirilir.
`timescale 1ns / 1ps

module tb_dqn_perf;
  import axi_pkg::*;

  // ════════════════════════════════════════════════
  // Clock & Reset
  // ════════════════════════════════════════════════
  logic clk;
  logic rstn;

  initial begin clk = 0; forever #5 clk = ~clk; end  // 10ns = 100 MHz

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
  // Parametreler
  // ════════════════════════════════════════════════
  localparam int GRID_SIZE   = 8;
  localparam int MAX_STEPS   = 120;
  localparam int NUM_MAZES   = 5;

  // Q1.15 sabitleri
  localparam logic signed [15:0] LEAKY_ALPHA = 16'sh0148;  // 0.01

  // ════════════════════════════════════════════════
  // Labirent tanimlari
  // ════════════════════════════════════════════════
  logic maze_walls [0:NUM_MAZES-1][0:GRID_SIZE-1][0:GRID_SIZE-1];
  int maze_start_x [0:NUM_MAZES-1];
  int maze_start_y [0:NUM_MAZES-1];
  int maze_goal_x  [0:NUM_MAZES-1];
  int maze_goal_y  [0:NUM_MAZES-1];

  // ════════════════════════════════════════════════
  // Sonuc depolama
  // ════════════════════════════════════════════════
  int cpu_only_cycles    [0:NUM_MAZES-1];
  int dqn_parallel_cycles[0:NUM_MAZES-1];
  int cpu_only_steps     [0:NUM_MAZES-1];
  int dqn_parallel_steps [0:NUM_MAZES-1];

  // ════════════════════════════════════════════════
  // AXI sinyal tanimlari
  // ════════════════════════════════════════════════
  logic             drv_mem_read;
  logic             drv_mem_write;
  logic [1:0]       drv_mem_size;
  logic             drv_mem_unsigned;
  logic [31:0]      drv_addr;
  logic [31:0]      drv_wdata;
  logic [31:0]      drv_rdata;
  logic             drv_ready;

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
  // DUT Instantiation
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

  // Kullanilmayan slave portlarini baglama
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

  // ════════════════════════════════════════════════
  // Agirlik bellegi (148 eleman)
  // ════════════════════════════════════════════════
  logic signed [15:0] all_weights [0:147];

  task automatic load_weights_axi();
    axi_write(DQN_CTRL, 32'h0000_0009, 2'b10);  // enable=1, wt_load_mode=1
    axi_write(DQN_WT_ADDR, 32'h0000_0000, 2'b10);
    for (int i = 0; i < 148; i++) begin
      axi_write(DQN_WT_DATA, {{16{all_weights[i][15]}}, all_weights[i]}, 2'b10);
    end
    axi_write(DQN_CTRL, 32'h0000_0001, 2'b10);  // enable=1, wt_load_mode=0
  endtask

  // ════════════════════════════════════════════════
  // DQN AXI inference tetikleme ve bekleme
  // ════════════════════════════════════════════════
  task automatic run_inference_axi();
    logic [31:0] status;
    axi_write(DQN_CTRL, 32'h0000_0003, 2'b10);  // enable=1, start=1
    status = 32'h0;
    while (!(status & 32'h2)) begin
      axi_read(DQN_STATUS, 2'b10, status);
    end
  endtask

  // ════════════════════════════════════════════════
  // Duvar-duyarli State Vektoru Hesaplama
  //
  // standlone versiyonu ile ayni mantik:
  //   score = (goal_yonundeki_mesafe + arastirma_biasi) * duvar_faktoru
  // ════════════════════════════════════════════════
  function automatic logic signed [15:0] compute_attractiveness(
    input int delta,
    input int can_move
  );
    logic signed [31:0] goal_score;
    logic signed [31:0] base_score;
    logic signed [31:0] total;
    begin
      if (delta > 0)
        goal_score = (delta * 32768 * 6) / (GRID_SIZE * 10);
      else
        goal_score = 0;
      base_score = 1638;  // 0.05 in Q1.15
      total = goal_score + base_score;
      if (can_move == 0)
        total = total / 100;
      if (total > 32767) total = 32767;
      if (total < 0) total = 0;
      compute_attractiveness = total[15:0];
    end
  endfunction

  function automatic int can_move_dir(
    input int maze_id, input int px, input int py, input int dir
  );
    int nx, ny;
    begin
      nx = px; ny = py;
      case (dir)
        0: ny = py - 1;
        1: ny = py + 1;
        2: nx = px - 1;
        3: nx = px + 1;
      endcase
      if (nx < 0 || nx >= GRID_SIZE || ny < 0 || ny >= GRID_SIZE)
        can_move_dir = 0;
      else if (maze_walls[maze_id][ny][nx])
        can_move_dir = 0;
      else
        can_move_dir = 1;
    end
  endfunction

  // ════════════════════════════════════════════════
  // CPU-Only Yazilim DQN Inference
  // ════════════════════════════════════════════════
  function automatic int cpu_inference(
    input logic signed [15:0] state_in [0:3],
    input logic signed [15:0] weights [0:147],
    output logic [1:0] action
  );
    logic signed [15:0] fc1_w [0:3][0:15];
    logic signed [15:0] fc1_b [0:15];
    logic signed [15:0] fc2_w [0:15][0:3];
    logic signed [15:0] fc2_b [0:3];
    logic signed [15:0] hidden [0:15];
    logic signed [15:0] q_val [0:3];
    logic signed [31:0] sum;
    logic signed [15:0] trunc;
    logic signed [15:0] biased;
    logic signed [31:0] relu_prod;
    int cycles;

    cycles = 0;

    // Agirliklari bellekten oku
    for (int i = 0; i < 4; i++)
      for (int j = 0; j < 16; j++) begin
        fc1_w[i][j] = weights[i*16 + j];
        cycles++;
      end
    for (int i = 0; i < 16; i++) begin
      fc1_b[i] = weights[64 + i];
      cycles++;
    end
    for (int i = 0; i < 16; i++)
      for (int j = 0; j < 4; j++) begin
        fc2_w[i][j] = weights[80 + i*4 + j];
        cycles++;
      end
    for (int i = 0; i < 4; i++) begin
      fc2_b[i] = weights[144 + i];
      cycles++;
    end

    // FC1: 16 noron
    for (int j = 0; j < 16; j++) begin
      sum = 32'sd0;
      for (int i = 0; i < 4; i++) begin
        sum = sum + (32'(state_in[i]) * 32'(fc1_w[i][j]));
        cycles += 3;
      end
      trunc = sum[30:15];
      cycles++;
      biased = trunc + fc1_b[j];
      cycles++;
      if (biased >= 16'sh0000) begin
        hidden[j] = biased;
        cycles++;
      end else begin
        relu_prod = 32'(biased) * 32'(LEAKY_ALPHA);
        hidden[j] = relu_prod[30:15];
        cycles += 3;
      end
    end

    // FC2: 4 cikis noronu
    for (int j = 0; j < 4; j++) begin
      sum = 32'sd0;
      for (int i = 0; i < 16; i++) begin
        sum = sum + (32'(hidden[i]) * 32'(fc2_w[i][j]));
        cycles += 3;
      end
      trunc = sum[30:15];
      cycles++;
      q_val[j] = trunc + fc2_b[j];
      cycles++;
    end

    // Argmax
    begin
      logic signed [15:0] max_val;
      logic [1:0] max_idx;
      max_val = q_val[0];
      max_idx = 2'd0;
      cycles++;
      for (int i = 1; i < 4; i++) begin
        if (q_val[i] > max_val) begin
          max_val = q_val[i];
          max_idx = i[1:0];
        end
        cycles++;
      end
      action = max_idx;
    end

    return cycles;
  endfunction

  // ════════════════════════════════════════════════
  // Hareket fonksiyonu
  // ════════════════════════════════════════════════
  function automatic void apply_action(
    input  int maze_id,
    input  logic [1:0] action,
    inout  int pos_x,
    inout  int pos_y
  );
    int new_x, new_y;
    new_x = pos_x;
    new_y = pos_y;
    case (action)
      2'd0: new_y = pos_y - 1;
      2'd1: new_y = pos_y + 1;
      2'd2: new_x = pos_x - 1;
      2'd3: new_x = pos_x + 1;
    endcase
    if (new_x >= 0 && new_x < GRID_SIZE && new_y >= 0 && new_y < GRID_SIZE) begin
      if (!maze_walls[maze_id][new_y][new_x]) begin
        pos_x = new_x;
        pos_y = new_y;
      end
    end
  endfunction

  // ════════════════════════════════════════════════
  // Labirent gorsellestirme
  // ════════════════════════════════════════════════
  task automatic print_maze(
    input int maze_id,
    input int px, input int py
  );
    string line_str;
    for (int yy = 0; yy < GRID_SIZE; yy++) begin
      line_str = "    ";
      for (int xx = 0; xx < GRID_SIZE; xx++) begin
        if (xx == px && yy == py)
          line_str = {line_str, "A "};
        else if (xx == maze_goal_x[maze_id] && yy == maze_goal_y[maze_id])
          line_str = {line_str, "G "};
        else if (xx == maze_start_x[maze_id] && yy == maze_start_y[maze_id])
          line_str = {line_str, "S "};
        else if (maze_walls[maze_id][yy][xx])
          line_str = {line_str, "# "};
        else
          line_str = {line_str, ". "};
      end
      $display("%s", line_str);
    end
  endtask

  // ════════════════════════════════════════════════
  // Ortam guncelleme CPU is yuku
  // ════════════════════════════════════════════════
  localparam int ENV_UPDATE_CYCLES = 15;

  // ════════════════════════════════════════════════
  // Ana Test Sekansi
  // ════════════════════════════════════════════════
  logic [31:0] rd_val;
  logic signed [15:0] current_state [0:3];
  logic [1:0] action;
  int cycle_counter;
  int step_count;

  initial begin
    $display("");
    $display("================================================================");
    $display("  DQN Performans Testi - CPU-only vs DQN+CPU Paralel");
    $display("  5 Karmasik Labirent, 8x8 Grid, Duvar-Duyarli Navigasyon");
    $display("  (AXI uzerinden tam donanim testi - Vivado XSIM)");
    $display("================================================================");

    // Sinyal baslangic
    drv_mem_read     = 1'b0;
    drv_mem_write    = 1'b0;
    drv_mem_size     = 2'b10;
    drv_mem_unsigned = 1'b0;
    drv_addr         = '0;
    drv_wdata        = '0;

    // Agirliklari sifirla
    for (int i = 0; i < 148; i++) all_weights[i] = 16'sh0000;

    // ════════════════════════════════════════════════
    // 5 KARMASIK LABIRENT TANIMLARI
    // ════════════════════════════════════════════════
    for (int m = 0; m < NUM_MAZES; m++)
      for (int y = 0; y < GRID_SIZE; y++)
        for (int x = 0; x < GRID_SIZE; x++)
          maze_walls[m][y][x] = 1'b0;

    // -- Labirent 0: Tek Genis Yatay Bariyer --
    maze_start_x[0] = 0; maze_start_y[0] = 0;
    maze_goal_x[0]  = 7; maze_goal_y[0]  = 7;
    for (int i = 0; i <= 5; i++) maze_walls[0][3][i] = 1'b1;

    // -- Labirent 1: Cift Yatay Bariyer --
    maze_start_x[1] = 0; maze_start_y[1] = 0;
    maze_goal_x[1]  = 7; maze_goal_y[1]  = 7;
    for (int i = 0; i <= 5; i++) maze_walls[1][2][i] = 1'b1;
    for (int i = 0; i <= 5; i++) maze_walls[1][5][i] = 1'b1;

    // -- Labirent 2: Uc Yatay Bariyer (basamakli) --
    maze_start_x[2] = 0; maze_start_y[2] = 0;
    maze_goal_x[2]  = 7; maze_goal_y[2]  = 7;
    for (int i = 0; i <= 4; i++) maze_walls[2][1][i] = 1'b1;
    for (int i = 0; i <= 5; i++) maze_walls[2][3][i] = 1'b1;
    for (int i = 0; i <= 6; i++) maze_walls[2][5][i] = 1'b1;

    // -- Labirent 3: Dort Yatay Bariyer --
    maze_start_x[3] = 0; maze_start_y[3] = 0;
    maze_goal_x[3]  = 7; maze_goal_y[3]  = 7;
    for (int i = 0; i <= 4; i++) maze_walls[3][1][i] = 1'b1;
    for (int i = 6; i <= 7; i++) maze_walls[3][2][i] = 1'b1;
    for (int i = 0; i <= 5; i++) maze_walls[3][4][i] = 1'b1;
    for (int i = 0; i <= 6; i++) maze_walls[3][6][i] = 1'b1;

    // -- Labirent 4: Bes Yatay Bariyer (En Karmasik) --
    maze_start_x[4] = 0; maze_start_y[4] = 0;
    maze_goal_x[4]  = 7; maze_goal_y[4]  = 7;
    for (int i = 0; i <= 3; i++) maze_walls[4][1][i] = 1'b1;
    for (int i = 5; i <= 7; i++) maze_walls[4][2][i] = 1'b1;
    for (int i = 0; i <= 5; i++) maze_walls[4][4][i] = 1'b1;
    for (int i = 4; i <= 6; i++) maze_walls[4][5][i] = 1'b1;
    for (int i = 0; i <= 6; i++) maze_walls[4][6][i] = 1'b1;

    // ════════════════════════════════════════════════
    // Agirlik kurulumu — identity-like (FC1 diag 0.5, FC2 diag 0.5)
    // Q[i] = state[i] * 0.25
    // ════════════════════════════════════════════════
    all_weights[0*16 + 0] = 16'sh4000;  // 0.5
    all_weights[1*16 + 1] = 16'sh4000;
    all_weights[2*16 + 2] = 16'sh4000;
    all_weights[3*16 + 3] = 16'sh4000;
    all_weights[80 + 0*4 + 0] = 16'sh4000;
    all_weights[80 + 1*4 + 1] = 16'sh4000;
    all_weights[80 + 2*4 + 2] = 16'sh4000;
    all_weights[80 + 3*4 + 3] = 16'sh4000;

    // Reset
    rstn = 1'b0;
    repeat(10) @(posedge clk);
    rstn = 1'b1;
    repeat(5) @(posedge clk);

    // Agirliklari AXI uzerinden yukle
    load_weights_axi();
    $display("\n  [HAZIRLIK] Agirliklar yuklendi, wt_loaded kontrol...");
    axi_read(DQN_STATUS, 2'b10, rd_val);
    if (rd_val[2]) $display("  [HAZIRLIK] wt_loaded = 1, BASARILI");
    else begin
      $display("  [HATA] wt_loaded = 0, agirlik yuklemesi BASARISIZ!");
      $finish;
    end

    // ════════════════════════════════════════════════
    // BOLUM 1: CPU-Only Labirent Cozme
    // ════════════════════════════════════════════════
    $display("\n================================================================");
    $display("  BOLUM 1: CPU-Only Hesaplama ile Labirent Cozme");
    $display("  (Tum DQN inference yazilimda, cycle cycle hesaplanir)");
    $display("================================================================");

    for (int m = 0; m < NUM_MAZES; m++) begin
      int pos_x, pos_y;
      int delta_x, delta_y;
      pos_x = maze_start_x[m];
      pos_y = maze_start_y[m];
      cycle_counter = 0;
      step_count = 0;

      $display("\n  -- Labirent %0d --", m);
      $display("    Baslangic: (%0d,%0d) -> Hedef: (%0d,%0d)",
               pos_x, pos_y, maze_goal_x[m], maze_goal_y[m]);
      print_maze(m, pos_x, pos_y);

      while (step_count < MAX_STEPS && !(pos_x == maze_goal_x[m] && pos_y == maze_goal_y[m])) begin
        delta_x = maze_goal_x[m] - pos_x;
        delta_y = maze_goal_y[m] - pos_y;

        current_state[0] = compute_attractiveness(-delta_y, can_move_dir(m, pos_x, pos_y, 0));
        current_state[1] = compute_attractiveness( delta_y, can_move_dir(m, pos_x, pos_y, 1));
        current_state[2] = compute_attractiveness(-delta_x, can_move_dir(m, pos_x, pos_y, 2));
        current_state[3] = compute_attractiveness( delta_x, can_move_dir(m, pos_x, pos_y, 3));

        cycle_counter += ENV_UPDATE_CYCLES;
        cycle_counter += cpu_inference(current_state, all_weights, action);
        apply_action(m, action, pos_x, pos_y);
        step_count++;
      end

      cpu_only_cycles[m] = cycle_counter;
      cpu_only_steps[m]  = step_count;

      if (pos_x == maze_goal_x[m] && pos_y == maze_goal_y[m])
        $display("    COZULDU! Adim: %0d, CPU Cycle: %0d", step_count, cycle_counter);
      else
        $display("    COZULEMEDI (max adim asildi) Adim: %0d, CPU Cycle: %0d", step_count, cycle_counter);
    end

    // ════════════════════════════════════════════════
    // BOLUM 2: DQN+CPU Paralel Labirent Cozme (AXI)
    // ════════════════════════════════════════════════
    $display("\n================================================================");
    $display("  BOLUM 2: DQN Hizlandirici + CPU Paralel Labirent Cozme");
    $display("  (DQN AXI donanim inference, gercek clock cycle olculur)");
    $display("================================================================");

    for (int m = 0; m < NUM_MAZES; m++) begin
      int pos_x, pos_y;
      int start_time, end_time;
      int delta_x, delta_y;

      pos_x = maze_start_x[m];
      pos_y = maze_start_y[m];
      step_count = 0;

      $display("\n  -- Labirent %0d --", m);
      $display("    Baslangic: (%0d,%0d) -> Hedef: (%0d,%0d)",
               pos_x, pos_y, maze_goal_x[m], maze_goal_y[m]);
      print_maze(m, pos_x, pos_y);

      start_time = $time / 10;

      while (step_count < MAX_STEPS && !(pos_x == maze_goal_x[m] && pos_y == maze_goal_y[m])) begin
        delta_x = maze_goal_x[m] - pos_x;
        delta_y = maze_goal_y[m] - pos_y;

        current_state[0] = compute_attractiveness(-delta_y, can_move_dir(m, pos_x, pos_y, 0));
        current_state[1] = compute_attractiveness( delta_y, can_move_dir(m, pos_x, pos_y, 1));
        current_state[2] = compute_attractiveness(-delta_x, can_move_dir(m, pos_x, pos_y, 2));
        current_state[3] = compute_attractiveness( delta_x, can_move_dir(m, pos_x, pos_y, 3));

        // State'i DQN'e yaz
        axi_write(DQN_STATE_0, {{16{current_state[0][15]}}, current_state[0]}, 2'b10);
        axi_write(DQN_STATE_1, {{16{current_state[1][15]}}, current_state[1]}, 2'b10);
        axi_write(DQN_STATE_2, {{16{current_state[2][15]}}, current_state[2]}, 2'b10);
        axi_write(DQN_STATE_3, {{16{current_state[3][15]}}, current_state[3]}, 2'b10);

        // Inference baslat ve bekle
        run_inference_axi();

        // Sonucu oku (argmax)
        axi_read(DQN_STATUS, 2'b10, rd_val);
        action = rd_val[5:4];

        // Hareketi uygula
        apply_action(m, action, pos_x, pos_y);
        step_count++;
      end

      end_time = $time / 10;
      dqn_parallel_cycles[m] = end_time - start_time;
      dqn_parallel_steps[m]  = step_count;

      if (pos_x == maze_goal_x[m] && pos_y == maze_goal_y[m])
        $display("    COZULDU! Adim: %0d, DQN+CPU Cycle: %0d", step_count, dqn_parallel_cycles[m]);
      else
        $display("    COZULEMEDI (max adim asildi) Adim: %0d, DQN+CPU Cycle: %0d", step_count, dqn_parallel_cycles[m]);
    end

    // ════════════════════════════════════════════════
    // BOLUM 3: Detayli Karsilastirma Raporu
    // ════════════════════════════════════════════════
    $display("\n================================================================");
    $display("  PERFORMANS KARSILASTIRMA TABLOSU");
    $display("================================================================");
    $display("");
    $display("  Labirent | Adim | CPU-Only(cyc) | DQN+CPU(cyc) | Hizlanma");
    $display("  ---------+------+---------------+--------------+---------");

    begin
      int total_cpu, total_dqn;
      int total_steps_cpu, total_steps_dqn;
      real speedup;
      total_cpu = 0;
      total_dqn = 0;
      total_steps_cpu = 0;
      total_steps_dqn = 0;

      for (int m = 0; m < NUM_MAZES; m++) begin
        if (dqn_parallel_cycles[m] > 0)
          speedup = real'(cpu_only_cycles[m]) / real'(dqn_parallel_cycles[m]);
        else
          speedup = 0.0;
        $display("    %0d      |  %3d |    %8d   |   %8d   | %5.2fx",
                 m, cpu_only_steps[m], cpu_only_cycles[m], dqn_parallel_cycles[m], speedup);
        total_cpu += cpu_only_cycles[m];
        total_dqn += dqn_parallel_cycles[m];
        total_steps_cpu += cpu_only_steps[m];
        total_steps_dqn += dqn_parallel_steps[m];
      end

      $display("  ---------+------+---------------+--------------+---------");
      if (total_dqn > 0)
        speedup = real'(total_cpu) / real'(total_dqn);
      else
        speedup = 0.0;
      $display("  TOPLAM   |  %3d |    %8d   |   %8d   | %5.2fx",
               total_steps_cpu, total_cpu, total_dqn, speedup);

      $display("");
      $display("  -- DETAYLI ANALIZ --");
      $display("");
      $display("  [CPU-Only Mod]");
      $display("    Her adimda tam 4->16->4 DQN inference yazilimda hesaplandi:");
      $display("    - Agirlik yukleme : 148 cycle (148 weight load)");
      $display("    - FC1 katmani     : 16 noron x (4 MAC + bias + LeakyReLU)");
      $display("    - FC2 katmani     : 4 noron x (16 MAC + bias)");
      $display("    - Argmax          : 4 karsilastirma");
      if (total_steps_cpu > 0)
        $display("    - Adim basina     : %0d inference + %0d ortam = %0d cycle",
                 (total_cpu - total_steps_cpu * ENV_UPDATE_CYCLES) / total_steps_cpu,
                 ENV_UPDATE_CYCLES,
                 total_cpu / total_steps_cpu);
      $display("");
      $display("  [DQN+CPU Paralel Mod]");
      $display("    DQN hizlandirici donanim inference (AXI uzerinden):");
      $display("    - FC1 katmani     : 16 cycle (1 noron/cycle, 4 paralel MAC)");
      $display("    - FC2 katmani     : 16 cycle (4 grup x 4 noron)");
      $display("    - Argmax          : 1 cycle");
      $display("    - Toplam inference: 33 clock cycle");
      $display("    - AXI overhead    : state yazma + start + polling + sonuc okuma");
      if (total_steps_dqn > 0)
        $display("    - Adim basina     : ~%0d cycle (inference + AXI overhead)",
                 total_dqn / total_steps_dqn);
      $display("");
      $display("  [Kazanim]");
      $display("    Toplam CPU cycle   : %0d", total_cpu);
      $display("    Toplam DQN+CPU cyc : %0d", total_dqn);
      $display("    Genel hizlanma     : %.2fx", speedup);
    end

    $display("");
    $display("================================================================");
    $display("  DQN Performans Testi TAMAMLANDI");
    $display("================================================================");
    $display("");

    $finish;
  end

  // Timeout
  initial begin
    #100_000_000;
    $display("[TIMEOUT] Simulasyon zaman asimi!");
    $finish;
  end

endmodule
