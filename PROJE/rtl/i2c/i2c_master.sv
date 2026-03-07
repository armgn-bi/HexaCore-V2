// filepath: rtl/i2c/i2c_master.sv
// I2C Master Controller — 7-bit adres, 8-bit veri
// Open-drain SDA/SCL çıkışları (0=çek, 1=bırak)
// Desteklenen hızlar: Standard (100 kHz), Fast (400 kHz) — clock divider ile
//
// Komut arayüzü:
//   cmd_i[2:0] :  001=START, 010=WRITE_BYTE, 011=READ_ACK, 100=READ_NACK, 101=STOP
//   cmd_valid_i:  1-cycle pulse ile komut verilir
//   cmd_ready_o:  komut kabul edilebilir
//   tx_data_i  :  yazılacak byte (WRITE_BYTE komutuyla)
//   rx_data_o  :  okunan byte (READ_ACK/READ_NACK sonrası)
//   rx_valid_o :  okunan byte geçerli (1-cycle pulse)
//   ack_err_o  :  slave ACK vermedi (NACK geldi)
//   busy_o     :  işlem devam ediyor
`timescale 1ns / 1ps

module i2c_master (
  input  logic        clk_i,
  input  logic        rstn_i,

  // ── Kontrol ────────────────────────────────────
  input  logic        en_i,            // Modül etkin
  input  logic [15:0] prescale_i,      // SCL periyot = 4 * (prescale + 1) clock cycle

  // ── Komut arayüzü ─────────────────────────────
  input  logic [2:0]  cmd_i,           // Komut kodu
  input  logic        cmd_valid_i,     // Komut geçerli (pulse)
  output logic        cmd_ready_o,     // Yeni komut alınabilir

  input  logic [7:0]  tx_data_i,       // Yazılacak byte
  output logic [7:0]  rx_data_o,       // Okunan byte
  output logic        rx_valid_o,      // Okunan byte geçerli (pulse)
  output logic        ack_err_o,       // NACK hatası (sticky)
  output logic        busy_o,          // İşlem devam ediyor

  // ── I2C fiziksel hatlar (active-low open-drain) ──
  output logic        scl_oe_o,        // SCL output enable (1=drive low, 0=release)
  output logic        sda_oe_o,        // SDA output enable (1=drive low, 0=release)
  input  logic        scl_i,           // SCL giriş (readback)
  input  logic        sda_i            // SDA giriş (readback)
);

  // ════════════════════════════════════════════════
  // Komut Kodları
  // ════════════════════════════════════════════════
  localparam logic [2:0] CMD_NOP       = 3'b000;
  localparam logic [2:0] CMD_START     = 3'b001;
  localparam logic [2:0] CMD_WRITE     = 3'b010;
  localparam logic [2:0] CMD_READ_ACK  = 3'b011;
  localparam logic [2:0] CMD_READ_NACK = 3'b100;
  localparam logic [2:0] CMD_STOP      = 3'b101;

  // ════════════════════════════════════════════════
  // FSM Durumları
  // ════════════════════════════════════════════════
  typedef enum logic [3:0] {
    S_IDLE       = 4'd0,
    S_START_1    = 4'd1,   // SDA↓ while SCL=1
    S_START_2    = 4'd2,   // SCL↓
    S_WRITE_BIT  = 4'd3,   // SDA set → SCL↑ → SCL↓
    S_WRITE_ACK  = 4'd4,   // Release SDA, read ACK
    S_READ_BIT   = 4'd5,   // Release SDA, SCL↑ → sample → SCL↓
    S_READ_SEND  = 4'd6,   // Send ACK/NACK
    S_STOP_1     = 4'd7,   // SDA↓ while SCL=0
    S_STOP_2     = 4'd8,   // SCL↑
    S_STOP_3     = 4'd9    // SDA↑ while SCL=1 → STOP
  } fsm_state_t;

  fsm_state_t state_q;

  // ════════════════════════════════════════════════
  // SCL Clock Divider — 4 fazlı: low1, rise, high, fall
  // Toplam SCL periyot = 4 * (prescale_i + 1) clock cycle
  // ════════════════════════════════════════════════
  logic [15:0] clk_cnt_q;
  logic [1:0]  phase_q;     // 00=low1, 01=rise, 10=high, 11=fall
  logic        phase_tick;  // Her faz geçişinde 1-cycle pulse

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      clk_cnt_q <= 16'd0;
      phase_q   <= 2'b00;
    end else if (state_q == S_IDLE) begin
      clk_cnt_q <= 16'd0;
      phase_q   <= 2'b00;
    end else begin
      if (clk_cnt_q >= prescale_i) begin
        clk_cnt_q <= 16'd0;
        phase_q   <= phase_q + 2'd1;
      end else begin
        clk_cnt_q <= clk_cnt_q + 16'd1;
      end
    end
  end

  assign phase_tick = (clk_cnt_q >= prescale_i);

  // ════════════════════════════════════════════════
  // Sinyal senkronizasyonu (metastability)
  // ════════════════════════════════════════════════
  logic sda_sync1, sda_sync2;
  logic scl_sync1, scl_sync2;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      sda_sync1 <= 1'b1;
      sda_sync2 <= 1'b1;
      scl_sync1 <= 1'b1;
      scl_sync2 <= 1'b1;
    end else begin
      sda_sync1 <= sda_i;
      sda_sync2 <= sda_sync1;
      scl_sync1 <= scl_i;
      scl_sync2 <= scl_sync1;
    end
  end

  // ════════════════════════════════════════════════
  // Dahili register'lar
  // ════════════════════════════════════════════════
  logic [7:0]  shift_q;        // TX/RX kaydırma yazmacı
  logic [2:0]  bit_cnt_q;      // Bit sayacı (0–7)
  logic        send_nack_q;    // READ_NACK komutu mu?
  logic [2:0]  cmd_q;          // Latch'lenmiş komut
  logic        ack_err_q;      // Sticky NACK hatası

  // ════════════════════════════════════════════════
  // Çıkış atamaları
  // ════════════════════════════════════════════════
  assign cmd_ready_o = (state_q == S_IDLE) && en_i;
  assign busy_o      = (state_q != S_IDLE);
  assign ack_err_o   = ack_err_q;

  // ════════════════════════════════════════════════
  // Ana FSM
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      state_q     <= S_IDLE;
      scl_oe_o    <= 1'b0;   // release (high-Z → pull-up)
      sda_oe_o    <= 1'b0;   // release
      shift_q     <= 8'd0;
      bit_cnt_q   <= 3'd0;
      send_nack_q <= 1'b0;
      cmd_q       <= CMD_NOP;
      ack_err_q   <= 1'b0;
      rx_data_o   <= 8'd0;
      rx_valid_o  <= 1'b0;
    end else begin
      // Varsayılan pulse sinyalleri
      rx_valid_o <= 1'b0;

      case (state_q)
        // ── IDLE: Komut bekle ──────────────────────
        S_IDLE: begin
          if (en_i && cmd_valid_i) begin
            cmd_q <= cmd_i;
            case (cmd_i)
              CMD_START: begin
                // SDA ve SCL'yi önce serbest bırak (repeated start için)
                sda_oe_o <= 1'b0;  // release SDA (high)
                scl_oe_o <= 1'b0;  // release SCL (high)
                state_q  <= S_START_1;
              end
              CMD_WRITE: begin
                shift_q   <= tx_data_i;
                bit_cnt_q <= 3'd7;
                state_q   <= S_WRITE_BIT;
                scl_oe_o  <= 1'b1;  // SCL low before data
              end
              CMD_READ_ACK: begin
                send_nack_q <= 1'b0;
                bit_cnt_q   <= 3'd7;
                shift_q     <= 8'd0;
                state_q     <= S_READ_BIT;
                scl_oe_o    <= 1'b1;  // SCL low
                sda_oe_o    <= 1'b0;  // release SDA for slave
              end
              CMD_READ_NACK: begin
                send_nack_q <= 1'b1;
                bit_cnt_q   <= 3'd7;
                shift_q     <= 8'd0;
                state_q     <= S_READ_BIT;
                scl_oe_o    <= 1'b1;  // SCL low
                sda_oe_o    <= 1'b0;  // release SDA for slave
              end
              CMD_STOP: begin
                sda_oe_o <= 1'b1;  // SDA low
                scl_oe_o <= 1'b1;  // SCL low
                state_q  <= S_STOP_1;
              end
              default: ; // NOP
            endcase
          end
        end

        // ── START Condition ──────────────────────
        // START = SDA ↓ while SCL = 1
        S_START_1: begin
          if (phase_tick && phase_q == 2'b10) begin
            // ortada: SCL yüksek, SDA'yı düşür
            sda_oe_o <= 1'b1;  // drive SDA low
            state_q  <= S_START_2;
          end
        end

        S_START_2: begin
          if (phase_tick && phase_q == 2'b11) begin
            // SCL'yi düşür
            scl_oe_o <= 1'b1;  // drive SCL low
            state_q  <= S_IDLE;
          end
        end

        // ── WRITE: MSB-first 8 bit ────────────────
        S_WRITE_BIT: begin
          // Faz 00 (low1): SDA'yı ayarla
          if (phase_tick && phase_q == 2'b00) begin
            sda_oe_o <= !shift_q[7];  // bit=1→release(0), bit=0→drive(1)
          end
          // Faz 01 (rise): SCL'yi bırak
          if (phase_tick && phase_q == 2'b01) begin
            scl_oe_o <= 1'b0;  // release SCL (high)
          end
          // Faz 11 (fall): SCL'yi düşür, bir sonraki bite geç
          if (phase_tick && phase_q == 2'b11) begin
            scl_oe_o <= 1'b1;  // drive SCL low
            if (bit_cnt_q == 3'd0) begin
              // 8 bit gönderildi → ACK oku
              sda_oe_o <= 1'b0;  // release SDA for ACK
              state_q  <= S_WRITE_ACK;
            end else begin
              shift_q   <= {shift_q[6:0], 1'b0};
              bit_cnt_q <= bit_cnt_q - 3'd1;
            end
          end
        end

        // ── WRITE ACK: Slave'den ACK oku ──────────
        S_WRITE_ACK: begin
          // Faz 01: SCL'yi bırak → slave ACK sürer
          if (phase_tick && phase_q == 2'b01) begin
            scl_oe_o <= 1'b0;  // release SCL
          end
          // Faz 10 (high orta): SDA örnekle
          if (phase_tick && phase_q == 2'b10) begin
            if (sda_sync2) begin
              // SDA=1 → NACK
              ack_err_q <= 1'b1;
            end
          end
          // Faz 11 (fall): SCL düşür, IDLE'a dön
          if (phase_tick && phase_q == 2'b11) begin
            scl_oe_o <= 1'b1;  // drive SCL low
            state_q  <= S_IDLE;
          end
        end

        // ── READ: MSB-first 8 bit ─────────────────
        S_READ_BIT: begin
          // Faz 01: SCL'yi bırak
          if (phase_tick && phase_q == 2'b01) begin
            scl_oe_o <= 1'b0;  // release SCL
          end
          // Faz 10 (high orta): SDA'yı örnekle
          if (phase_tick && phase_q == 2'b10) begin
            shift_q <= {shift_q[6:0], sda_sync2};
          end
          // Faz 11 (fall): SCL düşür
          if (phase_tick && phase_q == 2'b11) begin
            scl_oe_o <= 1'b1;  // drive SCL low
            if (bit_cnt_q == 3'd0) begin
              // 8 bit okundu → ACK/NACK gönder
              rx_data_o  <= {shift_q[6:0], sda_sync2};
              state_q    <= S_READ_SEND;
            end else begin
              bit_cnt_q <= bit_cnt_q - 3'd1;
            end
          end
        end

        // ── READ ACK/NACK: Master ACK veya NACK gönder ──
        S_READ_SEND: begin
          // Faz 00: SDA'yı ayarla (ACK=SDA low → oe=1, NACK=SDA high → oe=0)
          if (phase_tick && phase_q == 2'b00) begin
            sda_oe_o <= !send_nack_q;  // ACK: drive low(1), NACK: release(0)
          end
          // Faz 01: SCL bırak
          if (phase_tick && phase_q == 2'b01) begin
            scl_oe_o <= 1'b0;
          end
          // Faz 11: SCL düşür, tamamla
          if (phase_tick && phase_q == 2'b11) begin
            scl_oe_o   <= 1'b1;  // drive SCL low
            sda_oe_o   <= 1'b0;  // release SDA
            rx_valid_o <= 1'b1;
            state_q    <= S_IDLE;
          end
        end

        // ── STOP Condition ───────────────────────
        // STOP = SDA ↑ while SCL = 1
        S_STOP_1: begin
          // Faz 00: SDA low, SCL low olduğundan emin ol
          if (phase_tick && phase_q == 2'b00) begin
            sda_oe_o <= 1'b1;  // drive SDA low
          end
          // Faz 01: SCL'yi bırak
          if (phase_tick && phase_q == 2'b01) begin
            scl_oe_o <= 1'b0;  // release SCL
            state_q  <= S_STOP_2;
          end
        end

        S_STOP_2: begin
          // Faz 10: SCL yüksekken SDA'yı bırak → STOP
          if (phase_tick && phase_q == 2'b10) begin
            sda_oe_o <= 1'b0;  // release SDA → rises → STOP
            state_q  <= S_STOP_3;
          end
        end

        S_STOP_3: begin
          // Bir faz bekle ve IDLE'a dön
          if (phase_tick && phase_q == 2'b11) begin
            state_q <= S_IDLE;
          end
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule
