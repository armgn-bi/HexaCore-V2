// filepath: rtl/uart/uart_tx.sv
// UART Transmitter — 8N1 (8 data, no parity, 1 stop)
// Baud rate tick girişiyle sürülür (16x oversampled tick).
// FSM: IDLE → START → DATA(0..7) → STOP
`timescale 1ns / 1ps

module uart_tx (
  input  logic        clk_i,
  input  logic        rstn_i,

  // Kontrol
  input  logic        tx_en_i,        // TX etkin
  input  logic        baud_tick_i,    // 16x baud rate tick (1-cycle pulse)

  // Veri arayüzü
  input  logic [7:0]  tx_data_i,      // Gönderilecek byte
  input  logic        tx_valid_i,     // Veri hazır (1-cycle pulse)
  output logic        tx_ready_o,     // Yeni veri kabul edilebilir

  // Seri çıkış
  output logic        tx_o            // UART TX hattı
);

  // ════════════════════════════════════════════════
  // FSM Durumları
  // ════════════════════════════════════════════════
  typedef enum logic [1:0] {
    S_IDLE  = 2'b00,
    S_START = 2'b01,
    S_DATA  = 2'b10,
    S_STOP  = 2'b11
  } tx_state_t;

  tx_state_t state_q, state_next;

  logic [7:0]  shift_q;       // Kaydırma yazmacı (LSB-first)
  logic [2:0]  bit_cnt_q;     // Gönderilen bit sayacı (0–7)
  logic [3:0]  tick_cnt_q;    // 16x oversampling sayacı (0–15)

  // ════════════════════════════════════════════════
  // TX ready — sadece IDLE durumunda yeni veri kabul ederiz
  // ════════════════════════════════════════════════
  assign tx_ready_o = (state_q == S_IDLE) && tx_en_i;

  // ════════════════════════════════════════════════
  // Sequential Logic
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      state_q    <= S_IDLE;
      shift_q    <= 8'hFF;
      bit_cnt_q  <= 3'd0;
      tick_cnt_q <= 4'd0;
      tx_o       <= 1'b1;     // idle-high
    end else begin
      case (state_q)
        // ── IDLE: Yeni veri gelene kadar bekle ─────
        S_IDLE: begin
          tx_o <= 1'b1;
          if (tx_en_i && tx_valid_i) begin
            shift_q    <= tx_data_i;
            tick_cnt_q <= 4'd0;
            state_q    <= S_START;
          end
        end

        // ── START bit: 1 bit süresi (16 tick) ──────
        S_START: begin
          tx_o <= 1'b0;   // start bit = 0
          if (baud_tick_i) begin
            if (tick_cnt_q == 4'd15) begin
              tick_cnt_q <= 4'd0;
              bit_cnt_q  <= 3'd0;
              state_q    <= S_DATA;
            end else begin
              tick_cnt_q <= tick_cnt_q + 4'd1;
            end
          end
        end

        // ── DATA: 8 bit, LSB-first ─────────────────
        S_DATA: begin
          tx_o <= shift_q[0];
          if (baud_tick_i) begin
            if (tick_cnt_q == 4'd15) begin
              tick_cnt_q <= 4'd0;
              shift_q    <= {1'b0, shift_q[7:1]};   // sağa kaydır
              if (bit_cnt_q == 3'd7) begin
                state_q <= S_STOP;
              end else begin
                bit_cnt_q <= bit_cnt_q + 3'd1;
              end
            end else begin
              tick_cnt_q <= tick_cnt_q + 4'd1;
            end
          end
        end

        // ── STOP bit: 1 bit süresi (16 tick) ───────
        S_STOP: begin
          tx_o <= 1'b1;   // stop bit = 1
          if (baud_tick_i) begin
            if (tick_cnt_q == 4'd15) begin
              tick_cnt_q <= 4'd0;
              state_q    <= S_IDLE;
            end else begin
              tick_cnt_q <= tick_cnt_q + 4'd1;
            end
          end
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule
