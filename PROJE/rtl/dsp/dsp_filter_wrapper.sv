// filepath: rtl/dsp/dsp_filter_wrapper.sv
// DSP FIR Filtre — AXI4-Lite Slave Wrapper
// MATLAB HDL Coder çıktısı dsphdl_FIRFilter modülünü AXI4-Lite bus'a bağlar.
//
// ┌────────────────────────────────────────────────────────┐
// │  Register Map (Offset from DSP_BASE = 0x4000_1000)    │
// ├────────┬────────────┬─────────────────────────────────┤
// │ Offset │ Name       │ Description                     │
// ├────────┼────────────┼─────────────────────────────────┤
// │ 0x00   │ CTRL       │ [0] enable (enb)                │
// │        │            │ [1] soft_reset (syncReset pulse) │
// │        │            │ [2] start (tek cycle pulse)      │
// ├────────┼────────────┼─────────────────────────────────┤
// │ 0x04   │ STATUS     │ [0] busy (transaction devam)    │
// │        │            │ [1] out_valid (çıkış hazır)     │
// ├────────┼────────────┼─────────────────────────────────┤
// │ 0x08   │ DATA_IN    │ [15:0] dataIn (sfix16_En15)     │
// │        │            │  Yazılınca validIn pulse üretir  │
// ├────────┼────────────┼─────────────────────────────────┤
// │ 0x0C   │ DATA_OUT_L │ [31:0] dataOut[31:0]            │
// ├────────┼────────────┼─────────────────────────────────┤
// │ 0x10   │ DATA_OUT_H │ [0]    dataOut[32]              │
// └────────┴────────────┴─────────────────────────────────┘
//
// Filtre çekirdeği:  dsphdl_FIRFilter (HDL Coder output)
//   - clk, reset (active-high sync), enb
//   - dataIn  [15:0]  signed  sfix16_En15 (Q1.15)
//   - validIn
//   - dataOut [32:0]  signed  sfix33_En31
//   - validOut
`timescale 1ns / 1ps

module dsp_filter_wrapper
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH = AXI_ADDR_WIDTH,
  parameter int DATA_WIDTH = AXI_DATA_WIDTH
)(
  input  logic                        clk_i,
  input  logic                        rstn_i,

  // ── AXI4-Lite Slave portları ────────────────────
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
  // Register offset tanımları
  // ════════════════════════════════════════════════
  localparam logic [7:0] REG_CTRL       = 8'h00;
  localparam logic [7:0] REG_STATUS     = 8'h04;
  localparam logic [7:0] REG_DATA_IN    = 8'h08;
  localparam logic [7:0] REG_DATA_OUT_L = 8'h0C;
  localparam logic [7:0] REG_DATA_OUT_H = 8'h10;

  // ════════════════════════════════════════════════
  // AXI4-Lite Slave arayüzü (generic wrapper instance)
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
  // Kontrol / Durum Register'ları
  // ════════════════════════════════════════════════
  logic        ctrl_enable;      // CTRL[0] — filtre clock enable
  logic        ctrl_soft_reset;  // CTRL[1] — 1 yazılınca tek cycle pulse
  logic        ctrl_start;       // CTRL[2] — 1 yazılınca tek cycle pulse

  logic signed [15:0] data_in_reg;   // DATA_IN register
  logic               data_in_wr;    // DATA_IN'e yazıldığını belirten sinyal

  // Filtre çıkışları
  logic signed [32:0] filter_dout;
  logic               filter_vout;

  // Çıkış latch'leri (validOut geldiğinde yakala)
  logic signed [32:0] dout_latched;
  logic               out_valid_flag;

  // ════════════════════════════════════════════════
  // Register yazma (AXI → Register)
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      ctrl_enable     <= 1'b0;
      ctrl_soft_reset <= 1'b0;
      ctrl_start      <= 1'b0;
      data_in_reg     <= 16'sd0;
      data_in_wr      <= 1'b0;
    end else begin
      // Tek cycle pulse'lar: her zaman temizle, yazma gelirse set et
      ctrl_soft_reset <= 1'b0;
      ctrl_start      <= 1'b0;
      data_in_wr      <= 1'b0;

      if (reg_wr_en) begin
        unique case (reg_addr)
          REG_CTRL: begin
            ctrl_enable     <= reg_wdata[0];
            ctrl_soft_reset <= reg_wdata[1];
            ctrl_start      <= reg_wdata[2];
          end
          REG_DATA_IN: begin
            data_in_reg <= reg_wdata[15:0];
            data_in_wr  <= 1'b1;
          end
          default: ; // diğer adresler read-only
        endcase
      end
    end
  end

  // ════════════════════════════════════════════════
  // Register okuma (Register → AXI)
  // ════════════════════════════════════════════════
  always_comb begin
    reg_rdata = '0;
    unique case (reg_addr)
      REG_CTRL:       reg_rdata = {29'd0, ctrl_start, ctrl_soft_reset, ctrl_enable};
      REG_STATUS:     reg_rdata = {30'd0, out_valid_flag, 1'b0};
      REG_DATA_IN:    reg_rdata = {{16{data_in_reg[15]}}, data_in_reg};  // sign-extended
      REG_DATA_OUT_L: reg_rdata = dout_latched[31:0];
      REG_DATA_OUT_H: reg_rdata = {31'd0, dout_latched[32]};
      default:        reg_rdata = 32'hDEAD_BEEF;
    endcase
  end

  // ════════════════════════════════════════════════
  // Çıkış verisi yakalama
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      dout_latched   <= 33'sd0;
      out_valid_flag <= 1'b0;
    end else begin
      if (filter_vout) begin
        dout_latched   <= filter_dout;
        out_valid_flag <= 1'b1;
      end
      // DATA_OUT_L okunduğunda flag'i temizle (status polling için)
      if (reg_rd_en && (reg_addr == REG_DATA_OUT_L))
        out_valid_flag <= 1'b0;
    end
  end

  // ════════════════════════════════════════════════
  // validIn pulse üreteci
  // DATA_IN register'a yazıldığında VEYA ctrl_start pulse'ında
  // tek cycle validIn üret
  // ════════════════════════════════════════════════
  logic filter_valid_in;
  assign filter_valid_in = data_in_wr | ctrl_start;

  // ════════════════════════════════════════════════
  // Reset dönüşümü
  // HDL Coder filtresi active-high reset kullanıyor
  // Bizim SoC active-low rstn_i kullanıyor
  // ════════════════════════════════════════════════
  logic filter_reset;
  assign filter_reset = !rstn_i;

  // ════════════════════════════════════════════════
  // HDL Coder FIR Filtre Instance
  // ════════════════════════════════════════════════
  dsphdl_FIRFilter u_fir_filter (
    .clk      (clk_i),
    .reset    (filter_reset),
    .enb      (ctrl_enable),
    .dataIn   (data_in_reg),
    .validIn  (filter_valid_in),
    .dataOut  (filter_dout),
    .validOut (filter_vout)
  );

endmodule
