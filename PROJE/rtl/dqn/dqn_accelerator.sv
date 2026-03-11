// filepath: rtl/dqn/dqn_accelerator.sv
// DQN Inference Accelerator — AXI4-Lite Slave Wrapper
// Kucuk DQN: 4->16->4 (FC1 + LeakyReLU + FC2)
// Q1.15 fixed-point, sadece inference, agirliklar AXI uzerinden yuklenir.
//
// ┌──────────────────────────────────────────────────────────┐
// │  Register Map (Offset from DQN_BASE = 0x4000_2000)      │
// ├────────┬────────────┬───────────────────────────────────┤
// │ Offset │ Name       │ Description                       │
// ├────────┼────────────┼───────────────────────────────────┤
// │ 0x00   │ CTRL       │ [0] enable                        │
// │        │            │ [1] start (self-clearing pulse)    │
// │        │            │ [2] soft_reset (self-clearing)     │
// │        │            │ [3] wt_load_mode                   │
// ├────────┼────────────┼───────────────────────────────────┤
// │ 0x04   │ STATUS     │ [0] busy                          │
// │        │            │ [1] done (sticky)                  │
// │        │            │ [2] wt_loaded                      │
// │        │            │ [7:4] argmax (2-bit, sifir ext)    │
// ├────────┼────────────┼───────────────────────────────────┤
// │ 0x08   │ STATE_0    │ [15:0] state[0] Q1.15             │
// │ 0x0C   │ STATE_1    │ [15:0] state[1] Q1.15             │
// │ 0x10   │ STATE_2    │ [15:0] state[2] Q1.15             │
// │ 0x14   │ STATE_3    │ [15:0] state[3] Q1.15             │
// ├────────┼────────────┼───────────────────────────────────┤
// │ 0x18   │ QVAL_0     │ [15:0] Q-value[0] Q1.15          │
// │ 0x1C   │ QVAL_1     │ [15:0] Q-value[1] Q1.15          │
// │ 0x20   │ QVAL_2     │ [15:0] Q-value[2] Q1.15          │
// │ 0x24   │ QVAL_3     │ [15:0] Q-value[3] Q1.15          │
// ├────────┼────────────┼───────────────────────────────────┤
// │ 0x28   │ QVAL_MAX   │ [15:0] Max Q-value Q1.15         │
// ├────────┼────────────┼───────────────────────────────────┤
// │ 0x2C   │ WT_ADDR    │ [7:0] Agirlik adresi (0-147)     │
// │        │            │ Auto-increment on WT_DATA write    │
// ├────────┼────────────┼───────────────────────────────────┤
// │ 0x30   │ WT_DATA    │ [15:0] Agirlik/bias Q1.15        │
// │        │            │ Write: kaydet + auto-increment     │
// │        │            │ Read: wt_addr'deki deger           │
// ├────────┼────────────┼───────────────────────────────────┤
// │ 0x34   │ CYCLE_CNT  │ [15:0] Inference suresi (cycles)  │
// ├────────┼────────────┼───────────────────────────────────┤
// │ 0x38   │ VERSION    │ 0x44514E01 ("DQN" + v1)           │
// └────────┴────────────┴───────────────────────────────────┘
//
// Agirlik bellek layout (148 girdi):
//   0-63:    FC1 weights  [input_idx*16 + output_idx]
//   64-79:   FC1 biases   [neuron_idx]
//   80-143:  FC2 weights  [80 + input_idx*4 + output_idx]
//   144-147: FC2 biases   [neuron_idx]
`timescale 1ns / 1ps

module dqn_accelerator
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH = AXI_ADDR_WIDTH,
  parameter int DATA_WIDTH = AXI_DATA_WIDTH
)(
  input  logic                        clk_i,
  input  logic                        rstn_i,

  // ── AXI4-Lite Slave portlari ────────────────────
  input  logic [ADDR_WIDTH-1:0]       s_axi_awaddr_i,
  input  logic [2:0]                  s_axi_awprot_i,
  input  logic                        s_axi_awvalid_i,
  output logic                        s_axi_awready_o,

  input  logic [DATA_WIDTH-1:0]       s_axi_wdata_i,
  input  logic [DATA_WIDTH/8-1:0]     s_axi_wstrb_i,
  input  logic                        s_axi_wvalid_i,
  output logic                        s_axi_wready_o,

  output logic [1:0]                  s_axi_bresp_o,
  output logic                        s_axi_bvalid_o,
  input  logic                        s_axi_bready_i,

  input  logic [ADDR_WIDTH-1:0]       s_axi_araddr_i,
  input  logic [2:0]                  s_axi_arprot_i,
  input  logic                        s_axi_arvalid_i,
  output logic                        s_axi_arready_o,

  output logic [DATA_WIDTH-1:0]       s_axi_rdata_o,
  output logic [1:0]                  s_axi_rresp_o,
  output logic                        s_axi_rvalid_o,
  input  logic                        s_axi_rready_i
);

  // ════════════════════════════════════════════════
  // Register offset tanimlari
  // ════════════════════════════════════════════════
  localparam logic [7:0] REG_CTRL      = 8'h00;
  localparam logic [7:0] REG_STATUS    = 8'h04;
  localparam logic [7:0] REG_STATE_0   = 8'h08;
  localparam logic [7:0] REG_STATE_1   = 8'h0C;
  localparam logic [7:0] REG_STATE_2   = 8'h10;
  localparam logic [7:0] REG_STATE_3   = 8'h14;
  localparam logic [7:0] REG_QVAL_0    = 8'h18;
  localparam logic [7:0] REG_QVAL_1    = 8'h1C;
  localparam logic [7:0] REG_QVAL_2    = 8'h20;
  localparam logic [7:0] REG_QVAL_3    = 8'h24;
  localparam logic [7:0] REG_QVAL_MAX  = 8'h28;
  localparam logic [7:0] REG_WT_ADDR   = 8'h2C;
  localparam logic [7:0] REG_WT_DATA   = 8'h30;
  localparam logic [7:0] REG_CYCLE_CNT = 8'h34;
  localparam logic [7:0] REG_VERSION   = 8'h38;

  // ════════════════════════════════════════════════
  // AXI4-Lite Slave arayuzu (generic wrapper instance)
  // ════════════════════════════════════════════════
  logic                  reg_wr_en;
  logic                  reg_rd_en;
  logic [7:0]            reg_addr;
  logic [DATA_WIDTH-1:0] reg_wdata;
  logic [DATA_WIDTH/8-1:0] reg_wstrb;
  logic [DATA_WIDTH-1:0] reg_rdata;

  axi_lite_slave #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .REG_ADDR_WIDTH (8)
  ) u_axi_slv (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    .s_axi_awaddr_i   (s_axi_awaddr_i),
    .s_axi_awprot_i   (s_axi_awprot_i),
    .s_axi_awvalid_i  (s_axi_awvalid_i),
    .s_axi_awready_o  (s_axi_awready_o),

    .s_axi_wdata_i    (s_axi_wdata_i),
    .s_axi_wstrb_i    (s_axi_wstrb_i),
    .s_axi_wvalid_i   (s_axi_wvalid_i),
    .s_axi_wready_o   (s_axi_wready_o),

    .s_axi_bresp_o    (s_axi_bresp_o),
    .s_axi_bvalid_o   (s_axi_bvalid_o),
    .s_axi_bready_i   (s_axi_bready_i),

    .s_axi_araddr_i   (s_axi_araddr_i),
    .s_axi_arprot_i   (s_axi_arprot_i),
    .s_axi_arvalid_i  (s_axi_arvalid_i),
    .s_axi_arready_o  (s_axi_arready_o),

    .s_axi_rdata_o    (s_axi_rdata_o),
    .s_axi_rresp_o    (s_axi_rresp_o),
    .s_axi_rvalid_o   (s_axi_rvalid_o),
    .s_axi_rready_i   (s_axi_rready_i),

    .reg_wr_en_o      (reg_wr_en),
    .reg_rd_en_o      (reg_rd_en),
    .reg_addr_o       (reg_addr),
    .reg_wdata_o      (reg_wdata),
    .reg_wstrb_o      (reg_wstrb),
    .reg_rdata_i      (reg_rdata)
  );

  // ════════════════════════════════════════════════
  // Kontrol Register'lari
  // ════════════════════════════════════════════════
  logic        ctrl_enable;       // CTRL[0]
  logic        ctrl_start;        // CTRL[1] — self-clearing pulse
  logic        ctrl_soft_reset;   // CTRL[2] — self-clearing pulse
  logic        ctrl_wt_load_mode; // CTRL[3]

  // State giris register'lari
  logic signed [15:0] state_in [0:3];

  // Agirlik adresi ve depolama
  logic [7:0]  wt_addr_q;
  logic        wt_loaded;   // tum 148 agirlik yuklendi mi

  // Agirlik bellegi
  logic signed [15:0] fc1_w [0:3][0:15];   // 64 agirlik
  logic signed [15:0] fc1_b [0:15];        // 16 bias
  logic signed [15:0] fc2_w [0:15][0:3];   // 64 agirlik
  logic signed [15:0] fc2_b [0:3];         // 4 bias

  // Core cikislari
  logic signed [15:0] q_val [0:3];
  logic               core_busy;
  logic               core_done;
  logic [1:0]         core_argmax;
  logic signed [15:0] core_q_max;
  logic [15:0]        core_cycle_cnt;

  // Done sticky flag
  logic done_sticky;

  // ════════════════════════════════════════════════
  // Agirlik okuma icin mux (WT_DATA read)
  // ════════════════════════════════════════════════
  logic signed [15:0] wt_read_data;
  logic [5:0] fc2_rd_off;  // FC2 read offset (module scope for Vivado compat)
  logic [5:0] fc2_wr_off;  // FC2 write offset (module scope for Vivado compat)
  assign fc2_wr_off = wt_addr_q - 8'd80;

  always_comb begin
    fc2_rd_off = wt_addr_q - 8'd80;
    wt_read_data = 16'sh0000;
    if (wt_addr_q < 8'd64) begin
      // FC1 weights: addr = input_idx*16 + output_idx
      wt_read_data = fc1_w[wt_addr_q[5:4]][wt_addr_q[3:0]];
    end else if (wt_addr_q < 8'd80) begin
      // FC1 biases: addr - 64
      wt_read_data = fc1_b[wt_addr_q - 8'd64];
    end else if (wt_addr_q < 8'd144) begin
      // FC2 weights: offset = addr - 80
      wt_read_data = fc2_w[fc2_rd_off[5:2]][fc2_rd_off[1:0]];
    end else if (wt_addr_q < 8'd148) begin
      // FC2 biases: addr - 144
      wt_read_data = fc2_b[wt_addr_q - 8'd144];
    end
  end

  // ════════════════════════════════════════════════
  // Register yazma (AXI -> Register)
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      ctrl_enable       <= 1'b0;
      ctrl_start        <= 1'b0;
      ctrl_soft_reset   <= 1'b0;
      ctrl_wt_load_mode <= 1'b0;
      state_in[0]       <= 16'sh0000;
      state_in[1]       <= 16'sh0000;
      state_in[2]       <= 16'sh0000;
      state_in[3]       <= 16'sh0000;
      wt_addr_q         <= 8'd0;
      wt_loaded         <= 1'b0;
      done_sticky       <= 1'b0;

      for (int i = 0; i < 4; i++)
        for (int j = 0; j < 16; j++)
          fc1_w[i][j] <= 16'sh0000;
      for (int i = 0; i < 16; i++)
        fc1_b[i] <= 16'sh0000;
      for (int i = 0; i < 16; i++)
        for (int j = 0; j < 4; j++)
          fc2_w[i][j] <= 16'sh0000;
      for (int i = 0; i < 4; i++)
        fc2_b[i] <= 16'sh0000;
    end else begin
      // Self-clearing pulse'lar
      ctrl_start      <= 1'b0;
      ctrl_soft_reset <= 1'b0;

      // Core done sticky flag
      if (core_done && !done_sticky)
        done_sticky <= 1'b1;

      if (reg_wr_en) begin
        case (reg_addr)
          REG_CTRL: begin
            ctrl_enable       <= reg_wdata[0];
            ctrl_start        <= reg_wdata[1] && !ctrl_wt_load_mode;  // wt_load_mode'da start engellenir
            ctrl_soft_reset   <= reg_wdata[2];
            ctrl_wt_load_mode <= reg_wdata[3];
            // start yazildiginda done_sticky temizle
            if (reg_wdata[1])
              done_sticky <= 1'b0;
          end

          REG_STATE_0: state_in[0] <= reg_wdata[15:0];
          REG_STATE_1: state_in[1] <= reg_wdata[15:0];
          REG_STATE_2: state_in[2] <= reg_wdata[15:0];
          REG_STATE_3: state_in[3] <= reg_wdata[15:0];

          REG_WT_ADDR: begin
            wt_addr_q <= reg_wdata[7:0];
          end

          REG_WT_DATA: begin
            if (ctrl_wt_load_mode) begin
              // Agirligi kaydet
              if (wt_addr_q < 8'd64) begin
                fc1_w[wt_addr_q[5:4]][wt_addr_q[3:0]] <= reg_wdata[15:0];
              end else if (wt_addr_q < 8'd80) begin
                fc1_b[wt_addr_q - 8'd64] <= reg_wdata[15:0];
              end else if (wt_addr_q < 8'd144) begin
                fc2_w[fc2_wr_off[5:2]][fc2_wr_off[1:0]] <= reg_wdata[15:0];
              end else if (wt_addr_q < 8'd148) begin
                fc2_b[wt_addr_q - 8'd144] <= reg_wdata[15:0];
              end

              // Auto-increment
              if (wt_addr_q < 8'd147)
                wt_addr_q <= wt_addr_q + 8'd1;
              else begin
                wt_addr_q <= 8'd0;
                wt_loaded <= 1'b1;
              end
            end
          end

          default: ; // diger adresler read-only
        endcase
      end
    end
  end

  // ════════════════════════════════════════════════
  // Register okuma (Register -> AXI)
  // ════════════════════════════════════════════════
  always_comb begin
    reg_rdata = '0;
    case (reg_addr)
      REG_CTRL:      reg_rdata = {28'd0, ctrl_wt_load_mode, ctrl_soft_reset, ctrl_start, ctrl_enable};
      REG_STATUS:    reg_rdata = {24'd0, 2'd0, core_argmax, wt_loaded, done_sticky, core_busy};
      REG_STATE_0:   reg_rdata = {{16{state_in[0][15]}}, state_in[0]};
      REG_STATE_1:   reg_rdata = {{16{state_in[1][15]}}, state_in[1]};
      REG_STATE_2:   reg_rdata = {{16{state_in[2][15]}}, state_in[2]};
      REG_STATE_3:   reg_rdata = {{16{state_in[3][15]}}, state_in[3]};
      REG_QVAL_0:    reg_rdata = {{16{q_val[0][15]}}, q_val[0]};
      REG_QVAL_1:    reg_rdata = {{16{q_val[1][15]}}, q_val[1]};
      REG_QVAL_2:    reg_rdata = {{16{q_val[2][15]}}, q_val[2]};
      REG_QVAL_3:    reg_rdata = {{16{q_val[3][15]}}, q_val[3]};
      REG_QVAL_MAX:  reg_rdata = {{16{core_q_max[15]}}, core_q_max};
      REG_WT_ADDR:   reg_rdata = {24'd0, wt_addr_q};
      REG_WT_DATA:   reg_rdata = {{16{wt_read_data[15]}}, wt_read_data};
      REG_CYCLE_CNT: reg_rdata = {16'd0, core_cycle_cnt};
      REG_VERSION:   reg_rdata = 32'h44514E01;  // "DQN" + version 1
      default:       reg_rdata = 32'hDEAD_BEEF;
    endcase
  end

  // ════════════════════════════════════════════════
  // DQN Inference Core Instance
  // ════════════════════════════════════════════════
  dqn_core u_dqn_core (
    .clk_i          (clk_i),
    .rstn_i         (rstn_i),
    .enable_i       (ctrl_enable),
    .start_i        (ctrl_start),
    .soft_reset_i   (ctrl_soft_reset),

    .state_in_i     (state_in),

    .fc1_w_i        (fc1_w),
    .fc1_b_i        (fc1_b),
    .fc2_w_i        (fc2_w),
    .fc2_b_i        (fc2_b),

    .q_val_o        (q_val),
    .busy_o         (core_busy),
    .done_o         (core_done),
    .argmax_o       (core_argmax),
    .q_max_o        (core_q_max),
    .cycle_cnt_o    (core_cycle_cnt)
  );

endmodule
