// filepath: rtl/i2c/i2c_master.sv
// I2C Master Controller (7-bit addressing, open-drain)
`timescale 1ns / 1ps

module i2c_master #(
  parameter PRESCALE_WIDTH = 16
)(
  input  logic                   clk_i,
  input  logic                   rstn_i,

  // Control
  input  logic                   en_i,
  input  logic [PRESCALE_WIDTH-1:0] prescale_i,

  // Command interface
  input  logic [2:0]             cmd_i,      // 001=START, 010=WRITE, 011=READ_ACK, 100=READ_NACK, 101=STOP
  input  logic [7:0]             tx_data_i,
  output logic [7:0]             rx_data_o,
  output logic                  busy_o,
  output logic                  ack_err_o,
  output logic                  rx_valid_o,
  output logic                  cmd_ready_o,

  // I2C Interface (open-drain)
  output logic                  sda_oe_o,   // Output enable (active-low)
  output logic                  scl_oe_o,   // Output enable (active-low)
  input  logic                  sda_i,
  input  logic                  scl_i
);

  // Clock divider (4x prescale for SCL)
  logic [PRESCALE_WIDTH+1:0] clk_cnt;
  logic scl_tick;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      clk_cnt <= '0;
    end else if (en_i && busy_o) begin
      if (clk_cnt >= {2'b0, prescale_i}) begin
        clk_cnt <= '0;
      end else begin
        clk_cnt <= clk_cnt + 1'b1;
      end
    end else begin
      clk_cnt <= '0;
    end
  end

  assign scl_tick = (clk_cnt == {2'b0, prescale_i});

  // Bit counter
  logic [3:0] bit_cnt;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      bit_cnt <= '0;
    end else if (en_i) begin
      if (scl_tick && busy_o) begin
        bit_cnt <= bit_cnt + 1'b1;
      end else if (!busy_o) begin
        bit_cnt <= '0;
      end
    end
  end

  // State machine
  typedef enum logic [2:0] {
    S_IDLE,
    S_START,
    S_ADDR,
    S_WRITE,
    S_READ,
    S_ACK,
    S_STOP
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
        if (cmd_i == 3'b001) begin  // START
          next_state = S_START;
        end
      end
      S_START: begin
        if (scl_tick && bit_cnt == 4'd0) begin
          next_state = S_ADDR;
        end
      end
      S_ADDR: begin
        if (scl_tick && bit_cnt == 4'd7) begin
          next_state = S_ACK;
        end
      end
      S_WRITE: begin
        if (scl_tick && bit_cnt == 4'd7) begin
          next_state = S_ACK;
        end
      end
      S_READ: begin
        if (scl_tick && bit_cnt == 4'd7) begin
          next_state = S_ACK;
        end
      end
      S_ACK: begin
        if (scl_tick && bit_cnt == 4'd0) begin
          if (cmd_i == 3'b101) begin  // STOP
            next_state = S_STOP;
          end else begin
            next_state = S_IDLE;
          end
        end
      end
      S_STOP: begin
        if (scl_tick && bit_cnt == 4'd0) begin
          next_state = S_IDLE;
        end
      end
      default: next_state = S_IDLE;
    endcase
  end

  // Shift register
  logic [7:0] tx_shift_reg, rx_shift_reg;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      tx_shift_reg <= '0;
      rx_shift_reg <= '0;
    end else if (en_i) begin
      if (state == S_IDLE && cmd_i == 3'b001) begin
        tx_shift_reg <= tx_data_i;
      end else if (scl_tick && busy_o && bit_cnt[0] == 1'b0) begin
        tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
        rx_shift_reg <= {rx_shift_reg[6:0], sda_i};
      end
    end
  end

  // Busy signal
  assign busy_o = (state != S_IDLE) && en_i;

  // ACK error detection
  logic ack_err_q;
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      ack_err_q <= 1'b0;
    end else if (en_i) begin
      if (state == S_ACK && scl_tick && bit_cnt == 4'd0 && sda_i) begin
        ack_err_q <= 1'b1;
      end else if (state == S_IDLE) begin
        ack_err_q <= 1'b0;
      end
    end
  end

  assign ack_err_o = ack_err_q;

  // RX valid
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      rx_valid_o <= 1'b0;
    end else if (en_i) begin
      if (state == S_ACK && scl_tick && bit_cnt == 4'd0) begin
        rx_valid_o <= 1'b1;
      end else if (state == S_IDLE) begin
        rx_valid_o <= 1'b0;
      end
    end
  end

  // RX data
  assign rx_data_o = rx_shift_reg;

  // Command ready
  assign cmd_ready_o = (state == S_IDLE) && en_i;

  // SCL generation (open-drain)
  logic scl_q;
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      scl_q <= 1'b1;
    end else if (en_i) begin
      case (state)
        S_IDLE: scl_q <= 1'b1;
        S_START: scl_q <= 1'b1;
        S_ADDR, S_WRITE, S_READ: begin
          if (scl_tick) scl_q <= ~scl_q;
        end
        S_ACK: scl_q <= 1'b0;
        S_STOP: scl_q <= 1'b1;
        default: scl_q <= 1'b1;
      endcase
    end else begin
      scl_q <= 1'b1;
    end
  end

  assign scl_oe_o = ~scl_q;  // Active-low output enable

  // SDA generation (open-drain)
  logic sda_q;
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      sda_q <= 1'b1;
    end else if (en_i) begin
      case (state)
        S_IDLE: sda_q <= 1'b1;
        S_START: begin
          if (bit_cnt == 4'd0) sda_q <= 1'b0;
        end
        S_ADDR, S_WRITE: begin
          sda_q <= tx_shift_reg[7];
        end
        S_READ: sda_q <= 1'b1;  // Release SDA for read
        S_ACK: begin
          if (bit_cnt == 4'd0) sda_q <= 1'b1;  // Release for ACK
        end
        S_STOP: begin
          if (bit_cnt == 4'd0) sda_q <= 1'b0;
        end
        default: sda_q <= 1'b1;
      endcase
    end else begin
      sda_q <= 1'b1;
    end
  end

  assign sda_oe_o = ~sda_q;  // Active-low output enable

endmodule
