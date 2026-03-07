// filepath: rtl/i2c/axi_i2c.sv
// AXI4-Lite I2C Master Periferal Wrapper
// axi_lite_slave generic bridge üzerinden register R/W arayüzü.
// I2C Master Core komut arayüzü ile kontrol edilir.
//
// ┌─────────────────────────────────────────────────────────────┐
// │  Register Map (Offset from I2C_BASE = 0x4000_0200)         │
// ├────────┬────────────┬──────┬────────────────────────────────┤
// │ Offset │ Name       │ R/W  │ Description                    │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x00   │ TXDATA     │  W   │ [7:0] Gönderilecek byte        │
// │        │            │  R   │ [7:0] = son yazılan TXDATA      │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x04   │ RXDATA     │  R   │ [7:0] Alınan byte              │
// │        │            │  W   │ yazma etkisiz                   │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x08   │ STATUS     │  R   │ [0] busy                       │
// │        │            │      │ [1] ack_err (sticky)            │
// │        │            │      │ [2] rx_valid                    │
// │        │            │      │ [3] cmd_ready                   │
// │        │            │      │ [4] arb_lost (reserved, =0)     │
// │        │            │  W   │ Yazma → sticky hataları temizle │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x0C   │ CTRL       │ R/W  │ [0] en (modül etkin)           │
// │        │            │      │ [1] ie (interrupt enable)       │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x10   │ PRESCALE   │ R/W  │ [15:0] SCL clock prescaler     │
// │        │            │      │ SCL period = 4*(PRESCALE+1) clk │
// │        │            │      │ 100MHz→100kHz: PRESCALE=249     │
// │        │            │      │ 100MHz→400kHz: PRESCALE=62      │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x14   │ CMD        │  W   │ [2:0] Komut kodu               │
// │        │            │      │  001=START, 010=WRITE_BYTE      │
// │        │            │      │  011=READ_ACK, 100=READ_NACK    │
// │        │            │      │  101=STOP                       │
// │        │            │      │ Yazma → komut tetiklenir        │
// │        │            │  R   │ [2:0] Son verilen komut         │
// └────────┴────────────┴──────┴────────────────────────────────┘
//
// Kullanım sırası (yazılımdan):
//   1. PRESCALE ← istenen SCL hızı
//   2. CTRL ← 0x01 (enable)
//   3. CMD ← 0x01 (START)       → STATUS.busy=1 olur, cmd_ready bekle
//   4. TXDATA ← slave_addr<<1   → CMD ← 0x02 (WRITE) → ACK kontrol
//   5. TXDATA ← data_byte       → CMD ← 0x02 (WRITE) → ACK kontrol
//   6. CMD ← 0x05 (STOP)
//
// Interrupt: irq = ie & (cmd_ready | ack_err)
`timescale 1ns / 1ps

module axi_i2c
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH       = AXI_ADDR_WIDTH,
  parameter int DATA_WIDTH       = AXI_DATA_WIDTH,
  parameter int DEFAULT_PRESCALE = 16'd249   // 100 MHz / (4*250) = 100 kHz
)(
  input  logic                        clk_i,
  input  logic                        rstn_i,

  // ── AXI4-Lite Slave portları ────────────────────
  input  logic [ADDR_WIDTH-1:0]       s_axi_awaddr_i,
  input  logic [2:0]                  s_axi_awprot_i,
  input  logic                        s_axi_awvalid_i,
  output logic                        s_axi_awready_o,

  input  logic [DATA_WIDTH-1:0]       s_axi_wdata_i,
  input  logic [DATA_WIDTH/8-1:0]     s_axi_wstrb_i,
  input  logic                        s_axi_wvalid_i,
  output logic                        s_axi_wready_o,

  output logic [1:0]                  s_axi_bresp_o,
  output logic                        s_axi_bvalid_o,
  input  logic                        s_axi_bready_i,

  input  logic [ADDR_WIDTH-1:0]       s_axi_araddr_i,
  input  logic [2:0]                  s_axi_arprot_i,
  input  logic                        s_axi_arvalid_i,
  output logic                        s_axi_arready_o,

  output logic [DATA_WIDTH-1:0]       s_axi_rdata_o,
  output logic [1:0]                  s_axi_rresp_o,
  output logic                        s_axi_rvalid_o,
  input  logic                        s_axi_rready_i,

  // ── I2C fiziksel hatlar (open-drain) ────────────
  output logic                        scl_oe_o,    // 1=drive low, 0=release
  input  logic                        scl_i,       // readback
  output logic                        sda_oe_o,    // 1=drive low, 0=release
  input  logic                        sda_i,       // readback

  // ── Interrupt çıkışı ───────────────────────────
  output logic                        irq_o
);

  // ════════════════════════════════════════════════
  // Register offset tanımları
  // ════════════════════════════════════════════════
  localparam logic [7:0] REG_TXDATA   = 8'h00;
  localparam logic [7:0] REG_RXDATA   = 8'h04;
  localparam logic [7:0] REG_STATUS   = 8'h08;
  localparam logic [7:0] REG_CTRL     = 8'h0C;
  localparam logic [7:0] REG_PRESCALE = 8'h10;
  localparam logic [7:0] REG_CMD      = 8'h14;

  // ════════════════════════════════════════════════
  // AXI4-Lite Slave Bridge
  // ════════════════════════════════════════════════
  logic                  reg_wr_en;
  logic                  reg_rd_en;
  logic [7:0]            reg_addr;
  logic [DATA_WIDTH-1:0] reg_wdata;
  logic [DATA_WIDTH/8-1:0] reg_wstrb;
  logic [DATA_WIDTH-1:0] reg_rdata;

  axi_lite_slave #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .REG_ADDR_WIDTH (8)
  ) u_axi_slv (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    .s_axi_awaddr_i   (s_axi_awaddr_i),
    .s_axi_awprot_i   (s_axi_awprot_i),
    .s_axi_awvalid_i  (s_axi_awvalid_i),
    .s_axi_awready_o  (s_axi_awready_o),

    .s_axi_wdata_i    (s_axi_wdata_i),
    .s_axi_wstrb_i    (s_axi_wstrb_i),
    .s_axi_wvalid_i   (s_axi_wvalid_i),
    .s_axi_wready_o   (s_axi_wready_o),

    .s_axi_bresp_o    (s_axi_bresp_o),
    .s_axi_bvalid_o   (s_axi_bvalid_o),
    .s_axi_bready_i   (s_axi_bready_i),

    .s_axi_araddr_i   (s_axi_araddr_i),
    .s_axi_arprot_i   (s_axi_arprot_i),
    .s_axi_arvalid_i  (s_axi_arvalid_i),
    .s_axi_arready_o  (s_axi_arready_o),

    .s_axi_rdata_o    (s_axi_rdata_o),
    .s_axi_rresp_o    (s_axi_rresp_o),
    .s_axi_rvalid_o   (s_axi_rvalid_o),
    .s_axi_rready_i   (s_axi_rready_i),

    .reg_wr_en_o      (reg_wr_en),
    .reg_rd_en_o      (reg_rd_en),
    .reg_addr_o       (reg_addr),
    .reg_wdata_o      (reg_wdata),
    .reg_wstrb_o      (reg_wstrb),
    .reg_rdata_i      (reg_rdata)
  );

  // ════════════════════════════════════════════════
  // Kontrol ve durum yazmaçları
  // ════════════════════════════════════════════════
  logic [31:0] ctrl_q;         // CTRL register
  logic [15:0] prescale_q;     // PRESCALE register
  logic [7:0]  txdata_q;       // Son yazılan TX data
  logic [2:0]  last_cmd_q;     // Son verilen komut

  // CTRL alanları
  wire i2c_en = ctrl_q[0];
  wire i2c_ie = ctrl_q[1];

  // ════════════════════════════════════════════════
  // I2C Master Core sinyalleri
  // ════════════════════════════════════════════════
  logic [2:0]  core_cmd;
  logic        core_cmd_valid;
  logic        core_cmd_ready;
  logic [7:0]  core_rx_data;
  logic        core_rx_valid;
  logic        core_ack_err;
  logic        core_busy;

  // rx_valid latch — STATUS okunana kadar tutulan bayrak
  logic        rx_valid_latch_q;

  // ════════════════════════════════════════════════
  // I2C Master Core Örneği
  // ════════════════════════════════════════════════
  i2c_master u_i2c_master (
    .clk_i       (clk_i),
    .rstn_i      (rstn_i),
    .en_i        (i2c_en),
    .prescale_i  (prescale_q),
    .cmd_i       (core_cmd),
    .cmd_valid_i (core_cmd_valid),
    .cmd_ready_o (core_cmd_ready),
    .tx_data_i   (txdata_q),
    .rx_data_o   (core_rx_data),
    .rx_valid_o  (core_rx_valid),
    .ack_err_o   (core_ack_err),
    .busy_o      (core_busy),
    .scl_oe_o    (scl_oe_o),
    .sda_oe_o    (sda_oe_o),
    .scl_i       (scl_i),
    .sda_i       (sda_i)
  );

  // ════════════════════════════════════════════════
  // Komut Tetikleme — CMD register'a yazıldığında
  // ════════════════════════════════════════════════
  logic cmd_trigger_q;   // 1-cycle pulse

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      cmd_trigger_q <= 1'b0;
      last_cmd_q    <= 3'b000;
    end else begin
      cmd_trigger_q <= 1'b0;  // varsayılan: temizle
      if (reg_wr_en && (reg_addr == REG_CMD)) begin
        cmd_trigger_q <= 1'b1;
        last_cmd_q    <= reg_wdata[2:0];
      end
    end
  end

  assign core_cmd       = last_cmd_q;
  assign core_cmd_valid = cmd_trigger_q;

  // ════════════════════════════════════════════════
  // RX Data Latch & rx_valid sticky
  // ════════════════════════════════════════════════
  logic [7:0] rx_data_q;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      rx_data_q       <= 8'd0;
      rx_valid_latch_q <= 1'b0;
    end else begin
      // Yeni RX verisi geldiğinde latch'le
      if (core_rx_valid) begin
        rx_data_q        <= core_rx_data;
        rx_valid_latch_q <= 1'b1;
      end
      // RXDATA register okunduğunda temizle
      if (reg_rd_en && (reg_addr == REG_RXDATA)) begin
        rx_valid_latch_q <= 1'b0;
      end
    end
  end

  // ════════════════════════════════════════════════
  // Sticky Error — STATUS yazılarak temizlenir
  // ════════════════════════════════════════════════
  logic ack_err_sticky_q;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      ack_err_sticky_q <= 1'b0;
    end else begin
      if (reg_wr_en && (reg_addr == REG_STATUS)) begin
        ack_err_sticky_q <= 1'b0;
      end else if (core_ack_err) begin
        ack_err_sticky_q <= 1'b1;
      end
    end
  end

  // ════════════════════════════════════════════════
  // Register Write Logic
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      ctrl_q     <= 32'd0;
      prescale_q <= DEFAULT_PRESCALE;
      txdata_q   <= 8'd0;
    end else if (reg_wr_en) begin
      case (reg_addr)
        REG_TXDATA:   txdata_q   <= reg_wdata[7:0];
        REG_CTRL:     ctrl_q     <= reg_wdata;
        REG_PRESCALE: prescale_q <= reg_wdata[15:0];
        // CMD yazma → cmd_trigger yukarıda
        // STATUS yazma → sticky clear yukarıda
        default: ;
      endcase
    end
  end

  // ════════════════════════════════════════════════
  // Register Read MUX
  // ════════════════════════════════════════════════
  always_comb begin
    case (reg_addr)
      REG_TXDATA:   reg_rdata = {24'd0, txdata_q};
      REG_RXDATA:   reg_rdata = {24'd0, rx_data_q};
      REG_STATUS:   reg_rdata = {27'd0, 1'b0,             // [4] arb_lost (reserved)
                                 core_cmd_ready,           // [3] cmd_ready
                                 rx_valid_latch_q,         // [2] rx_valid
                                 ack_err_sticky_q,         // [1] ack_err
                                 core_busy};               // [0] busy
      REG_CTRL:     reg_rdata = ctrl_q;
      REG_PRESCALE: reg_rdata = {16'd0, prescale_q};
      REG_CMD:      reg_rdata = {29'd0, last_cmd_q};
      default:      reg_rdata = 32'd0;
    endcase
  end

  // ════════════════════════════════════════════════
  // Interrupt Logic
  // irq = ie & (cmd_ready | ack_err)
  // ════════════════════════════════════════════════
  assign irq_o = i2c_ie & (core_cmd_ready | ack_err_sticky_q);

endmodule
