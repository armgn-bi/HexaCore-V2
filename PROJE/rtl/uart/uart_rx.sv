// filepath: rtl/uart/uart_rx.sv
// UART Receiver — 8N1 (8 data, no parity, 1 stop)
// 16x oversampling ile ortada örnekleme yapar.
// FSM: IDLE → START → DATA(0..7) → STOP
`timescale 1ns / 1ps

module uart_rx (
  input  logic        clk_i,
  input  logic        rstn_i,

  // Kontrol
  input  logic        rx_en_i,        // RX etkin
  input  logic        baud_tick_i,    // 16x baud rate tick (1-cycle pulse)

  // Seri giriş
  input  logic        rx_i,           // UART RX hattı

  // Veri arayüzü
  output logic [7:0]  rx_data_o,      // Alınan byte
  output logic        rx_valid_o,     // Veri hazır (1-cycle pulse)
  output logic        frame_err_o     // Çerçeve hatası (stop bit != 1)
);

  // ════════════════════════════════════════════════
  // RX girişi senkronizasyonu (metastability önleme)
  // ════════════════════════════════════════════════
  logic rx_sync1, rx_sync2;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      rx_sync1 <= 1'b1;
      rx_sync2 <= 1'b1;
    end else begin
      rx_sync1 <= rx_i;
      rx_sync2 <= rx_sync1;
    end
  end

  // ════════════════════════════════════════════════
  // FSM Durumları
  // ════════════════════════════════════════════════
  typedef enum logic [1:0] {
    S_IDLE  = 2'b00,
    S_START = 2'b01,
    S_DATA  = 2'b10,
    S_STOP  = 2'b11
  } rx_state_t;

  rx_state_t state_q;

  logic [7:0]  shift_q;       // Kaydırma yazmacı
  logic [2:0]  bit_cnt_q;     // Alınan bit sayacı (0–7)
  logic [3:0]  tick_cnt_q;    // 16x oversampling sayacı

  // ════════════════════════════════════════════════
  // Sequential Logic
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      state_q     <= S_IDLE;
      shift_q     <= 8'd0;
      bit_cnt_q   <= 3'd0;
      tick_cnt_q  <= 4'd0;
      rx_data_o   <= 8'd0;
      rx_valid_o  <= 1'b0;
      frame_err_o <= 1'b0;
    end else begin
      // Pulse sinyalleri varsayılan olarak sıfırla
      rx_valid_o  <= 1'b0;
      frame_err_o <= 1'b0;

      case (state_q)
        // ── IDLE: Start bit (düşen kenar) ara ──────
        S_IDLE: begin
          if (rx_en_i && !rx_sync2) begin
            // Start bit başlangıcı algılandı
            tick_cnt_q <= 4'd0;
            state_q    <= S_START;
          end
        end

        // ── START: Ortaya kadar say, doğrula ───────
        S_START: begin
          if (baud_tick_i) begin
            if (tick_cnt_q == 4'd7) begin
              // Bit süresinin ortasındayız
              if (!rx_sync2) begin
                // Start bit doğrulandı
                tick_cnt_q <= 4'd0;
                bit_cnt_q  <= 3'd0;
                state_q    <= S_DATA;
              end else begin
                // Yanlış alarm — geri dön
                state_q <= S_IDLE;
              end
            end else begin
              tick_cnt_q <= tick_cnt_q + 4'd1;
            end
          end
        end

        // ── DATA: 8 bit al, ortada örnekle ────────
        S_DATA: begin
          if (baud_tick_i) begin
            if (tick_cnt_q == 4'd15) begin
              tick_cnt_q <= 4'd0;
              // Ortada örnekle (16 tick sonra = bir sonraki bitin ortası)
              shift_q <= {rx_sync2, shift_q[7:1]};  // MSB'den doldur → LSB-first
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

        // ── STOP: Stop bit doğrula, veri çıkar ────
        S_STOP: begin
          if (baud_tick_i) begin
            if (tick_cnt_q == 4'd15) begin
              tick_cnt_q <= 4'd0;
              rx_data_o  <= shift_q;
              rx_valid_o <= 1'b1;
              if (!rx_sync2) begin
                // Stop bit 0 → çerçeve hatası
                frame_err_o <= 1'b1;
              end
              state_q <= S_IDLE;
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
