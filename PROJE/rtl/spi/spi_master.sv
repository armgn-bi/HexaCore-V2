// filepath: rtl/spi/spi_master.sv
// SPI Master Controller
// Desteklenen modlar: CPOL=0/1, CPHA=0/1 (SPI Mode 0–3)
// MSB-first, 8-bit transfer, configurable clock divider
// Multi-slave chip select (4 CS hattı, active-low)
//
// SPI Mode Tablosu:
//   Mode 0 (CPOL=0,CPHA=0): SCK idle=0, sample=rising,  shift=falling
//   Mode 1 (CPOL=0,CPHA=1): SCK idle=0, shift =rising,  sample=falling
//   Mode 2 (CPOL=1,CPHA=0): SCK idle=1, sample=falling, shift=rising
//   Mode 3 (CPOL=1,CPHA=1): SCK idle=1, shift =falling, sample=rising
//
// Kullanım:
//   1. cs_en_i=1 (CS assert)
//   2. start_i pulse → 8-bit transfer başlar
//   3. rx_valid_o pulse → rx_data_o geçerli
//   4. Tekrar start_i veya cs_en_i=0 (CS deassert)
`timescale 1ns / 1ps

module spi_master (
  input  logic        clk_i,
  input  logic        rstn_i,

  // ── Kontrol ────────────────────────────────────
  input  logic        en_i,            // Modül etkin
  input  logic [7:0]  clk_div_i,       // SCK bölücü: SCK half-period = (clk_div+1) clk cycle
  input  logic        cpol_i,          // Clock Polarity
  input  logic        cpha_i,          // Clock Phase

  // ── Transfer arayüzü ──────────────────────────
  input  logic        start_i,         // Transfer başlat (1-cycle pulse)
  output logic        ready_o,         // Yeni transfer kabul edilebilir

  input  logic [7:0]  tx_data_i,       // Gönderilecek byte
  output logic [7:0]  rx_data_o,       // Alınan byte
  output logic        rx_valid_o,      // Alınan byte geçerli (pulse)

  // ── Chip Select ────────────────────────────────
  input  logic [1:0]  cs_sel_i,        // Aktif slave (0–3)
  input  logic        cs_en_i,         // CS assert (1=active)

  // ── SPI fiziksel hatlar ────────────────────────
  output logic        sck_o,
  output logic        mosi_o,
  input  logic        miso_i,
  output logic [3:0]  ss_o             // Active-low chip select
);

  // ════════════════════════════════════════════════
  // CS Üretimi — active-low
  // ════════════════════════════════════════════════
  always_comb begin
    ss_o = 4'b1111;  // tümü deassert
    if (cs_en_i && en_i) begin
      ss_o[cs_sel_i] = 1'b0;  // seçili slave assert
    end
  end

  // ════════════════════════════════════════════════
  // FSM Durumları
  // ════════════════════════════════════════════════
  typedef enum logic [1:0] {
    S_IDLE     = 2'd0,
    S_LEADING  = 2'd1,   // SCK'nın ilk yarı periyodu (leading edge bekle)
    S_TRAILING = 2'd2    // SCK'nın ikinci yarı periyodu (trailing edge bekle)
  } fsm_state_t;

  fsm_state_t state_q;

  // ════════════════════════════════════════════════
  // Dahili yazmaçlar
  // ════════════════════════════════════════════════
  logic [7:0]  shift_tx_q;     // TX kaydırma yazmacı
  logic [7:0]  shift_rx_q;     // RX kaydırma yazmacı
  logic [2:0]  bit_cnt_q;      // Kalan bit sayısı (7 downto 0)
  logic [7:0]  clk_cnt_q;      // Clock bölücü sayacı
  logic        sck_q;          // SCK internal register

  assign ready_o = (state_q == S_IDLE) && en_i;
  assign sck_o   = sck_q;

  // MISO senkronizasyonu (2-FF metastability)
  logic miso_sync1, miso_sync2;
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      miso_sync1 <= 1'b0;
      miso_sync2 <= 1'b0;
    end else begin
      miso_sync1 <= miso_i;
      miso_sync2 <= miso_sync1;
    end
  end

  // Clock divider tick
  logic clk_tick;
  assign clk_tick = (clk_cnt_q >= clk_div_i);

  // ════════════════════════════════════════════════
  // Ana FSM
  //
  // Transfer akışı (CPHA=0):
  //   IDLE:     MOSI = tx[7] (setup before first edge)
  //   LEADING:  tick → toggle SCK → sample MISO
  //   TRAILING: tick → toggle SCK → shift TX, setup next MOSI
  //   8 bit sonra → IDLE
  //
  // Transfer akışı (CPHA=1):
  //   IDLE:     (MOSI don't care)
  //   LEADING:  tick → toggle SCK → setup MOSI
  //   TRAILING: tick → toggle SCK → sample MISO
  //   8 bit sonra → IDLE
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      state_q    <= S_IDLE;
      shift_tx_q <= 8'd0;
      shift_rx_q <= 8'd0;
      bit_cnt_q  <= 3'd7;
      clk_cnt_q  <= 8'd0;
      sck_q      <= 1'b0;
      mosi_o     <= 1'b0;
      rx_data_o  <= 8'd0;
      rx_valid_o <= 1'b0;
    end else begin
      rx_valid_o <= 1'b0;  // default: pulse temizle

      case (state_q)
        // ── IDLE ───────────────────────────────
        S_IDLE: begin
          sck_q     <= cpol_i;     // IDLE SCK seviyesi = CPOL
          clk_cnt_q <= 8'd0;
          bit_cnt_q <= 3'd7;

          if (en_i && start_i) begin
            shift_tx_q <= tx_data_i;
            shift_rx_q <= 8'd0;

            if (!cpha_i) begin
              // CPHA=0: ilk leading edge'de örnekleme olacak
              // → MOSI'yi şimdiden ayarla (setup time)
              mosi_o <= tx_data_i[7];
            end

            state_q <= S_LEADING;
          end
        end

        // ── LEADING half-period ────────────────
        // Yarı periyot bekle, sonra SCK toggle (leading edge)
        S_LEADING: begin
          if (clk_tick) begin
            clk_cnt_q <= 8'd0;
            sck_q     <= ~sck_q;   // ← Leading edge

            if (!cpha_i) begin
              // CPHA=0 → leading edge = SAMPLE
              shift_rx_q <= {shift_rx_q[6:0], miso_sync2};
            end else begin
              // CPHA=1 → leading edge = SETUP
              mosi_o <= shift_tx_q[7];
            end

            state_q <= S_TRAILING;
          end else begin
            clk_cnt_q <= clk_cnt_q + 8'd1;
          end
        end

        // ── TRAILING half-period ───────────────
        // Yarı periyot bekle, sonra SCK toggle (trailing edge)
        S_TRAILING: begin
          if (clk_tick) begin
            clk_cnt_q <= 8'd0;
            sck_q     <= ~sck_q;   // ← Trailing edge

            if (cpha_i) begin
              // CPHA=1 → trailing edge = SAMPLE
              shift_rx_q <= {shift_rx_q[6:0], miso_sync2};
            end

            if (bit_cnt_q == 3'd0) begin
              // ── 8 bit tamamlandı ──
              if (!cpha_i) begin
                // CPHA=0: tüm 8 bit leading'de örneklendi
                rx_data_o <= shift_rx_q;
              end else begin
                // CPHA=1: son bit bu trailing'de örnekleniyor
                rx_data_o <= {shift_rx_q[6:0], miso_sync2};
              end
              rx_valid_o <= 1'b1;
              state_q    <= S_IDLE;
            end else begin
              // ── Sonraki bit'e geç ──
              shift_tx_q <= {shift_tx_q[6:0], 1'b0};
              bit_cnt_q  <= bit_cnt_q - 3'd1;

              if (!cpha_i) begin
                // CPHA=0: trailing'de sonraki bit'i MOSI'ye koy
                mosi_o <= shift_tx_q[6];  // shift öncesi [6] = sonraki MSB
              end

              state_q <= S_LEADING;
            end
          end else begin
            clk_cnt_q <= clk_cnt_q + 8'd1;
          end
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule
