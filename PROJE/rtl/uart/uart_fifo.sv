// filepath: rtl/uart/uart_fifo.sv
// Basit Senkron FIFO — UART TX ve RX tamponları için
// Parametrik genişlik ve derinlik.
`timescale 1ns / 1ps

module uart_fifo #(
  parameter int DATA_WIDTH = 8,
  parameter int DEPTH      = 16     // 2'nin kuvveti olmalı
)(
  input  logic                    clk_i,
  input  logic                    rstn_i,

  // Yazma (push)
  input  logic [DATA_WIDTH-1:0]   wr_data_i,
  input  logic                    wr_en_i,

  // Okuma (pop)
  output logic [DATA_WIDTH-1:0]   rd_data_o,
  input  logic                    rd_en_i,

  // Durum
  output logic                    full_o,
  output logic                    empty_o,
  output logic [$clog2(DEPTH):0]  count_o      // Eleman sayısı
);

  localparam int PTR_W = $clog2(DEPTH);

  // ════════════════════════════════════════════════
  // Bellek ve işaretçiler
  // ════════════════════════════════════════════════
  logic [DATA_WIDTH-1:0] mem [DEPTH];

  logic [PTR_W:0] wr_ptr_q;    // Bir bit fazla — full/empty ayrımı için
  logic [PTR_W:0] rd_ptr_q;

  // ════════════════════════════════════════════════
  // Durum sinyalleri
  // ════════════════════════════════════════════════
  assign full_o  = (wr_ptr_q[PTR_W] != rd_ptr_q[PTR_W]) &&
                   (wr_ptr_q[PTR_W-1:0] == rd_ptr_q[PTR_W-1:0]);
  assign empty_o = (wr_ptr_q == rd_ptr_q);
  assign count_o = wr_ptr_q - rd_ptr_q;

  // ════════════════════════════════════════════════
  // Okuma verisi (kombinasyonel)
  // ════════════════════════════════════════════════
  assign rd_data_o = mem[rd_ptr_q[PTR_W-1:0]];

  // ════════════════════════════════════════════════
  // Sequential Logic
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
    end else begin
      // Yazma
      if (wr_en_i && !full_o) begin
        mem[wr_ptr_q[PTR_W-1:0]] <= wr_data_i;
        wr_ptr_q <= wr_ptr_q + 1;
      end
      // Okuma
      if (rd_en_i && !empty_o) begin
        rd_ptr_q <= rd_ptr_q + 1;
      end
    end
  end

endmodule
