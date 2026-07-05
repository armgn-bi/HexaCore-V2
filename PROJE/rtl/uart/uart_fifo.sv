// filepath: rtl/uart/uart_fifo.sv
// Parametrik Senkron FIFO
// UART TX/RX için 16x8 FIFO
`timescale 1ns / 1ps

module uart_fifo #(
  parameter DATA_WIDTH = 8,
  parameter DEPTH      = 16,
  parameter ADDR_WIDTH = $clog2(DEPTH)
)(
  input  logic                   clk_i,
  input  logic                   rstn_i,

  // Write port
  input  logic                   wr_en_i,
  input  logic [DATA_WIDTH-1:0]  wr_data_i,
  output logic                   full_o,

  // Read port
  input  logic                   rd_en_i,
  output logic [DATA_WIDTH-1:0]  rd_data_o,
  output logic                   empty_o
);

  // Memory
  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

  // Pointers
  logic [ADDR_WIDTH:0] wr_ptr, rd_ptr;
  logic [ADDR_WIDTH:0] wr_ptr_next, rd_ptr_next;

  // Full/Empty detection
  assign full_o  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                   (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
  assign empty_o = (wr_ptr == rd_ptr);

  // Write pointer update
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      wr_ptr <= '0;
    end else if (wr_en_i && !full_o) begin
      wr_ptr <= wr_ptr_next;
    end
  end

  assign wr_ptr_next = wr_ptr + 1'b1;

  // Read pointer update
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      rd_ptr <= '0;
    end else if (rd_en_i && !empty_o) begin
      rd_ptr <= rd_ptr_next;
    end
  end

  assign rd_ptr_next = rd_ptr + 1'b1;

  // Memory write
  always_ff @(posedge clk_i) begin
    if (wr_en_i && !full_o) begin
      mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data_i;
    end
  end

  // Memory read
  assign rd_data_o = mem[rd_ptr[ADDR_WIDTH-1:0]];

endmodule
