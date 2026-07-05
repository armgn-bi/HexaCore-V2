// filepath: rtl/spi/spi_master.sv
// SPI Master Controller (Mode 0-3, MSB-first, 8-bit)
`timescale 1ns / 1ps

module spi_master #(
  parameter CLK_DIV_WIDTH = 8
)(
  input  logic                   clk_i,
  input  logic                   rstn_i,

  // Control
  input  logic                   en_i,
  input  logic                   cpol_i,
  input  logic                   cpha_i,
  input  logic [CLK_DIV_WIDTH-1:0] clk_div_i,
  input  logic [3:0]             cs_sel_i,
  input  logic                   cs_en_i,

  // Data interface
  input  logic                   start_i,
  input  logic [7:0]             tx_data_i,
  output logic [7:0]             rx_data_o,
  output logic                   busy_o,
  output logic                   rx_valid_o,

  // SPI Interface
  output logic                   sck_o,
  output logic                   mosi_o,
  input  logic                   miso_i,
  output logic [3:0]             cs_o
);

  // Clock divider
  logic [CLK_DIV_WIDTH-1:0] clk_cnt;
  logic sck_edge;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      clk_cnt <= '0;
    end else if (en_i && busy_o) begin
      if (clk_cnt >= clk_div_i) begin
        clk_cnt <= '0;
      end else begin
        clk_cnt <= clk_cnt + 1'b1;
      end
    end else begin
      clk_cnt <= '0;
    end
  end

  assign sck_edge = (clk_cnt == clk_div_i);

  // Bit counter
  logic [3:0] bit_cnt;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      bit_cnt <= '0;
    end else if (en_i) begin
      if (start_i) begin
        bit_cnt <= '0;
      end else if (sck_edge && busy_o) begin
        bit_cnt <= bit_cnt + 1'b1;
      end
    end
  end

  // Shift register
  logic [7:0] tx_shift_reg, rx_shift_reg;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      tx_shift_reg <= '0;
      rx_shift_reg <= '0;
    end else if (en_i) begin
      if (start_i) begin
        tx_shift_reg <= tx_data_i;
        rx_shift_reg <= '0;
      end else if (sck_edge && busy_o) begin
        tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
        rx_shift_reg <= {rx_shift_reg[6:0], miso_i};
      end
    end
  end

  // State machine
  typedef enum logic [1:0] {
    S_IDLE,
    S_TRANSFER,
    S_DONE
  } state_t;

  state_t state, next_state;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      state <= S_IDLE;
    end else if (en_i) begin
      state <= next_state;
    end else begin
      state <= S_IDLE;
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      S_IDLE: begin
        if (start_i) begin
          next_state = S_TRANSFER;
        end
      end
      S_TRANSFER: begin
        if (sck_edge && bit_cnt == 4'd7) begin
          next_state = S_DONE;
        end
      end
      S_DONE: begin
        next_state = S_IDLE;
      end
      default: next_state = S_IDLE;
    endcase
  end

  // Busy signal
  assign busy_o = (state == S_TRANSFER) && en_i;

  // RX valid
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      rx_valid_o <= 1'b0;
    end else if (en_i) begin
      if (state == S_DONE) begin
        rx_valid_o <= 1'b1;
      end else if (start_i) begin
        rx_valid_o <= 1'b0;
      end
    end
  end

  // RX data
  assign rx_data_o = rx_shift_reg;

  // SCK generation based on CPOL/CPHA
  logic sck_q;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      sck_q <= cpol_i;
    end else if (en_i && busy_o) begin
      if (sck_edge) begin
        sck_q <= ~sck_q;
      end
    end else begin
      sck_q <= cpol_i;
    end
  end

  assign sck_o = sck_q;

  // MOSI output (MSB-first)
  assign mosi_o = tx_shift_reg[7];

  // Chip select
  assign cs_o = cs_en_i ? (~({4'b1, 4'b0} << cs_sel_i)) : 4'b1111;

endmodule
