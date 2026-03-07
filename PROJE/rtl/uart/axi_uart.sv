// filepath: rtl/uart/axi_uart.sv
// AXI4-Lite UART Periferal Wrapper
// axi_lite_slave generic bridge üzerinden register R/W arayüzü.
// TX/RX FIFO, baud rate divisor, interrupt desteği.
//
// ┌─────────────────────────────────────────────────────────────┐
// │  Register Map (Offset from UART_BASE = 0x4000_0000)        │
// ├────────┬────────────┬──────┬────────────────────────────────┤
// │ Offset │ Name       │ R/W  │ Description                    │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x00   │ TXDATA     │  W   │ [7:0] TX data → TX FIFO push   │
// │        │            │  R   │ [7:0] = 0x00 (reserved)        │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x04   │ RXDATA     │  R   │ [7:0] RX data ← RX FIFO pop   │
// │        │            │  W   │ yazma etkisiz                  │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x08   │ STATUS     │  R   │ [0] tx_full                    │
// │        │            │      │ [1] tx_empty                   │
// │        │            │      │ [2] rx_full                    │
// │        │            │      │ [3] rx_empty                   │
// │        │            │      │ [4] frame_err (sticky)         │
// │        │            │      │ [5] overrun_err (sticky)       │
// │        │            │  W   │ Yazma → sticky error temizle   │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x0C   │ CTRL       │ R/W  │ [0] tx_en                     │
// │        │            │      │ [1] rx_en                      │
// │        │            │      │ [2] tx_ie (TX empty IRQ en)    │
// │        │            │      │ [3] rx_ie (RX not-empty IRQ en)│
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x10   │ BAUD_DIV   │ R/W  │ [15:0] Baud rate divisor      │
// │        │            │      │ tick16 period = BAUD_DIV + 1   │
// │        │            │      │ BAUD_DIV = clk/(16*baud) - 1   │
// └────────┴────────────┴──────┴────────────────────────────────┘
//
// Interrupt: uart_irq_o = (tx_ie & tx_empty) | (rx_ie & ~rx_empty)
`timescale 1ns / 1ps

module axi_uart
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH  = AXI_ADDR_WIDTH,
  parameter int DATA_WIDTH  = AXI_DATA_WIDTH,
  parameter int TX_FIFO_DEPTH = 16,
  parameter int RX_FIFO_DEPTH = 16,
  parameter int DEFAULT_BAUD_DIV = 16'd53    // 100 MHz / (16*115200) - 1 ≈ 53
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
  input  logic                        s_axi_rready_i,

  // ── UART fiziksel hatlar ────────────────────────
  output logic                        tx_o,
  input  logic                        rx_i,

  // ── Interrupt çıkışı ───────────────────────────
  output logic                        irq_o
);

  // ════════════════════════════════════════════════
  // Register offset tanımları
  // ════════════════════════════════════════════════
  localparam logic [7:0] REG_TXDATA   = 8'h00;
  localparam logic [7:0] REG_RXDATA   = 8'h04;
  localparam logic [7:0] REG_STATUS   = 8'h08;
  localparam logic [7:0] REG_CTRL     = 8'h0C;
  localparam logic [7:0] REG_BAUD_DIV = 8'h10;

  // ════════════════════════════════════════════════
  // AXI4-Lite Slave Bridge (generic arayüz)
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
  // Kontrol ve durum yazmaçları
  // ════════════════════════════════════════════════
  logic [31:0] ctrl_q;        // CTRL register
  logic [15:0] baud_div_q;    // BAUD_DIV register
  logic        frame_err_q;   // Sticky frame error
  logic        overrun_err_q; // Sticky overrun error

  // CTRL alanları
  wire tx_en = ctrl_q[0];
  wire rx_en = ctrl_q[1];
  wire tx_ie = ctrl_q[2];
  wire rx_ie = ctrl_q[3];

  // ════════════════════════════════════════════════
  // Baud Rate Generator — 16x oversampling tick
  // Periyot = (baud_div_q + 1) clock cycle
  // ════════════════════════════════════════════════
  logic [15:0] baud_cnt_q;
  logic        baud_tick;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      baud_cnt_q <= 16'd0;
    end else begin
      if (baud_cnt_q >= baud_div_q) begin
        baud_cnt_q <= 16'd0;
      end else begin
        baud_cnt_q <= baud_cnt_q + 16'd1;
      end
    end
  end

  assign baud_tick = (baud_cnt_q >= baud_div_q);

  // ════════════════════════════════════════════════
  // TX FIFO
  // ════════════════════════════════════════════════
  logic [7:0]  tx_fifo_rdata;
  logic        tx_fifo_wr_en;
  logic        tx_fifo_rd_en;
  logic        tx_fifo_full;
  logic        tx_fifo_empty;

  uart_fifo #(
    .DATA_WIDTH (8),
    .DEPTH      (TX_FIFO_DEPTH)
  ) u_tx_fifo (
    .clk_i     (clk_i),
    .rstn_i    (rstn_i),
    .wr_data_i (reg_wdata[7:0]),
    .wr_en_i   (tx_fifo_wr_en),
    .rd_data_o (tx_fifo_rdata),
    .rd_en_i   (tx_fifo_rd_en),
    .full_o    (tx_fifo_full),
    .empty_o   (tx_fifo_empty),
    .count_o   ()   // kullanılmıyor şimdilik
  );

  // TX FIFO'ya yazma: TXDATA register'a yazıldığında
  assign tx_fifo_wr_en = reg_wr_en && (reg_addr == REG_TXDATA) && !tx_fifo_full;

  // ════════════════════════════════════════════════
  // UART TX Core
  // ════════════════════════════════════════════════
  logic tx_ready;

  uart_tx u_tx (
    .clk_i       (clk_i),
    .rstn_i      (rstn_i),
    .tx_en_i     (tx_en),
    .baud_tick_i (baud_tick),
    .tx_data_i   (tx_fifo_rdata),
    .tx_valid_i  (tx_fifo_rd_en),
    .tx_ready_o  (tx_ready),
    .tx_o        (tx_o)
  );

  // TX FIFO'dan okuma: TX hazır ve FIFO boş değilse
  assign tx_fifo_rd_en = tx_ready && !tx_fifo_empty;

  // ════════════════════════════════════════════════
  // RX FIFO
  // ════════════════════════════════════════════════
  logic [7:0]  rx_fifo_rdata;
  logic        rx_fifo_wr_en;
  logic        rx_fifo_rd_en;
  logic        rx_fifo_full;
  logic        rx_fifo_empty;

  // RX Core sinyalleri (FIFO'dan önce tanımlanmalı)
  logic [7:0] rx_data;
  logic       rx_valid;
  logic       rx_frame_err;

  uart_fifo #(
    .DATA_WIDTH (8),
    .DEPTH      (RX_FIFO_DEPTH)
  ) u_rx_fifo (
    .clk_i     (clk_i),
    .rstn_i    (rstn_i),
    .wr_data_i (rx_data),
    .wr_en_i   (rx_fifo_wr_en),
    .rd_data_o (rx_fifo_rdata),
    .rd_en_i   (rx_fifo_rd_en),
    .full_o    (rx_fifo_full),
    .empty_o   (rx_fifo_empty),
    .count_o   ()
  );

  // RX FIFO'dan okuma: RXDATA register okunduğunda
  assign rx_fifo_rd_en = reg_rd_en && (reg_addr == REG_RXDATA) && !rx_fifo_empty;

  // ════════════════════════════════════════════════
  // UART RX Core
  // ════════════════════════════════════════════════

  uart_rx u_rx (
    .clk_i       (clk_i),
    .rstn_i      (rstn_i),
    .rx_en_i     (rx_en),
    .baud_tick_i (baud_tick),
    .rx_i        (rx_i),
    .rx_data_o   (rx_data),
    .rx_valid_o  (rx_valid),
    .frame_err_o (rx_frame_err)
  );

  // RX verisini FIFO'ya yaz (RX çekirdeği geçerli veri ürettiğinde)
  assign rx_fifo_wr_en = rx_valid && !rx_fifo_full;

  // ════════════════════════════════════════════════
  // Sticky Error Flags
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      frame_err_q   <= 1'b0;
      overrun_err_q <= 1'b0;
    end else begin
      // STATUS register'a yazma → hataları temizle
      if (reg_wr_en && (reg_addr == REG_STATUS)) begin
        frame_err_q   <= 1'b0;
        overrun_err_q <= 1'b0;
      end else begin
        // Çerçeve hatası → sticky
        if (rx_frame_err)
          frame_err_q <= 1'b1;
        // Overrun: RX FIFO doluyken yeni veri gelirse
        if (rx_valid && rx_fifo_full)
          overrun_err_q <= 1'b1;
      end
    end
  end

  // ════════════════════════════════════════════════
  // Register Write Logic
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      ctrl_q     <= 32'd0;
      baud_div_q <= DEFAULT_BAUD_DIV;
    end else if (reg_wr_en) begin
      case (reg_addr)
        REG_CTRL:     ctrl_q     <= reg_wdata;
        REG_BAUD_DIV: baud_div_q <= reg_wdata[15:0];
        // TXDATA yazma tx_fifo_wr_en ile yönetiliyor
        // STATUS yazma → sticky clear yukarıda
        default: ;
      endcase
    end
  end

  // ════════════════════════════════════════════════
  // Register Read MUX
  // ════════════════════════════════════════════════
  always_comb begin
    case (reg_addr)
      REG_TXDATA:   reg_rdata = 32'd0;   // TX data write-only
      REG_RXDATA:   reg_rdata = {24'd0, rx_fifo_rdata};
      REG_STATUS:   reg_rdata = {26'd0, overrun_err_q, frame_err_q,
                                 rx_fifo_empty, rx_fifo_full,
                                 tx_fifo_empty, tx_fifo_full};
      REG_CTRL:     reg_rdata = ctrl_q;
      REG_BAUD_DIV: reg_rdata = {16'd0, baud_div_q};
      default:      reg_rdata = 32'd0;
    endcase
  end

  // ════════════════════════════════════════════════
  // Interrupt Logic
  // irq = (tx_ie & tx_fifo_empty) | (rx_ie & ~rx_fifo_empty)
  // ════════════════════════════════════════════════
  assign irq_o = (tx_ie & tx_fifo_empty) | (rx_ie & ~rx_fifo_empty);

endmodule
