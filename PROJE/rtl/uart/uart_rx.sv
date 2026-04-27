// filepath: rtl/uart/uart_rx.sv
// UART Receiver (8N1, 16x oversampling)
`timescale 1ns / 1ps

module uart_rx #(
  parameter BAUD_DIV_WIDTH = 16
)(
  input  logic                   clk_i,
  input  logic                   rstn_i,

  // Control
  input  logic                   rx_en_i,
  input  logic [BAUD_DIV_WIDTH-1:0] baud_div_i,

  // UART input
  input  logic                   uart_rx_i,

  // Data interface
  output logic                   rx_valid_o,
  output logic [7:0]             rx_data_o,
  output logic                   frame_err_o,
  output logic                   overrun_err_o
);

  // Input synchronization (2-FF metastability filter)
  logic uart_rx_meta, uart_rx_sync;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      uart_rx_meta <= 1'b1;
      uart_rx_sync <= 1'b1;
    end else if (rx_en_i) begin
      uart_rx_meta <= uart_rx_i;
      uart_rx_sync <= uart_rx_meta;
    end else begin
      uart_rx_sync <= 1'b1;
    end
  end

  // Baud rate generator (16x oversampling)
  logic [BAUD_DIV_WIDTH-1:0] baud_cnt;
  logic tick16;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      baud_cnt <= '0;
    end else if (rx_en_i) begin
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

  // Sample counter (0-15 for 16x oversampling)
  logic [3:0] sample_cnt;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      sample_cnt <= '0;
    end else if (rx_en_i) begin
      if (tick16) begin
        sample_cnt <= sample_cnt + 1'b1;
      end
    end
  end

  // Sample at middle (sample_cnt = 7)
  logic sample_tick;
  assign sample_tick = tick16 && (sample_cnt == 4'd7);

  // Bit counter (0-9: start, 8 data, stop)
  logic [3:0] bit_cnt;
  logic [7:0] rx_shift_reg;

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
    end else if (rx_en_i) begin
      state <= next_state;
    end else begin
      state <= S_IDLE;
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      S_IDLE: begin
        if (!uart_rx_sync) begin  // Start bit detected
          next_state = S_START;
        end
      end
      S_START: begin
        if (tick16 && sample_cnt == 4'd15) begin
          next_state = S_DATA;
        end
      end
      S_DATA: begin
        if (tick16 && sample_cnt == 4'd15 && bit_cnt == 4'd7) begin
          next_state = S_STOP;
        end
      end
      S_STOP: begin
        if (tick16 && sample_cnt == 4'd15) begin
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
    end else if (rx_en_i) begin
      if (state == S_IDLE) begin
        bit_cnt <= '0;
      end else if (state == S_DATA && tick16 && sample_cnt == 4'd15) begin
        bit_cnt <= bit_cnt + 1'b1;
      end
    end
  end

  // Shift register
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      rx_shift_reg <= '0;
    end else if (rx_en_i) begin
      if (state == S_DATA && sample_tick) begin
        rx_shift_reg <= {uart_rx_sync, rx_shift_reg[7:1]};
      end
    end
  end

  // Frame error detection
  logic frame_err_q;
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      frame_err_q <= 1'b0;
    end else if (rx_en_i) begin
      if (state == S_STOP && sample_tick && !uart_rx_sync) begin
        frame_err_q <= 1'b1;
      end else if (state == S_IDLE) begin
        frame_err_q <= 1'b0;
      end
    end
  end

  assign frame_err_o = frame_err_q;

  // Overrun error detection
  logic rx_valid_q;
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      rx_valid_q <= 1'b0;
    end else if (rx_en_i) begin
      rx_valid_q <= rx_valid_o;
    end
  end

  assign overrun_err_o = rx_valid_q && (state == S_STOP && sample_tick);

  // Valid output
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      rx_valid_o <= 1'b0;
    end else if (rx_en_i) begin
      if (state == S_STOP && sample_tick) begin
        rx_valid_o <= 1'b1;
      end else begin
        rx_valid_o <= 1'b0;
      end
    end else begin
      rx_valid_o <= 1'b0;
    end
  end

  // Data output
  assign rx_data_o = rx_shift_reg;

endmodule
