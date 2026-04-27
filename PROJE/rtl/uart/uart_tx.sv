// filepath: rtl/uart/uart_tx.sv
// UART Transmitter (8N1, 16x oversampling)
`timescale 1ns / 1ps

module uart_tx #(
  parameter BAUD_DIV_WIDTH = 16
)(
  input  logic                   clk_i,
  input  logic                   rstn_i,

  // Control
  input  logic                   tx_en_i,
  input  logic [BAUD_DIV_WIDTH-1:0] baud_div_i,

  // Data interface
  input  logic                   tx_start_i,
  input  logic [7:0]             tx_data_i,
  output logic                   tx_busy_o,

  // UART output
  output logic                   uart_tx_o
);

  // Baud rate generator (16x oversampling)
  logic [BAUD_DIV_WIDTH-1:0] baud_cnt;
  logic tick16;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      baud_cnt <= '0;
    end else if (tx_en_i) begin
      if (baud_cnt >= baud_div_i) begin
        baud_cnt <= '0;
      end else begin
        baud_cnt <= baud_cnt + 1'b1;
      end
    end else begin
      baud_cnt <= '0;
    end
  end

  assign tick16 = (baud_cnt == baud_div_i);

  // Bit counter (0-9: start, 8 data, stop)
  logic [3:0] bit_cnt;
  logic [7:0] tx_shift_reg;
  logic tx_active;

  // State machine
  typedef enum logic [1:0] {
    S_IDLE,
    S_START,
    S_DATA,
    S_STOP
  } state_t;

  state_t state, next_state;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      state <= S_IDLE;
    end else if (tx_en_i) begin
      state <= next_state;
    end else begin
      state <= S_IDLE;
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      S_IDLE: begin
        if (tx_start_i) begin
          next_state = S_START;
        end
      end
      S_START: begin
        if (tick16) begin
          next_state = S_DATA;
        end
      end
      S_DATA: begin
        if (tick16 && bit_cnt == 4'd7) begin
          next_state = S_STOP;
        end
      end
      S_STOP: begin
        if (tick16) begin
          next_state = S_IDLE;
        end
      end
      default: next_state = S_IDLE;
    endcase
  end

  // Bit counter
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      bit_cnt <= '0;
    end else if (tx_en_i) begin
      if (state == S_IDLE) begin
        bit_cnt <= '0;
      end else if (state == S_DATA && tick16) begin
        bit_cnt <= bit_cnt + 1'b1;
      end
    end
  end

  // Shift register
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      tx_shift_reg <= '0;
    end else if (tx_en_i) begin
      if (state == S_IDLE && tx_start_i) begin
        tx_shift_reg <= tx_data_i;
      end else if (state == S_DATA && tick16) begin
        tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
      end
    end
  end

  // TX output
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      uart_tx_o <= 1'b1;
    end else if (tx_en_i) begin
      case (state)
        S_IDLE:   uart_tx_o <= 1'b1;
        S_START:  uart_tx_o <= 1'b0;
        S_DATA:   uart_tx_o <= tx_shift_reg[0];
        S_STOP:   uart_tx_o <= 1'b1;
        default:  uart_tx_o <= 1'b1;
      endcase
    end else begin
      uart_tx_o <= 1'b1;
    end
  end

  // Busy signal
  assign tx_busy_o = (state != S_IDLE) && tx_en_i;

endmodule
