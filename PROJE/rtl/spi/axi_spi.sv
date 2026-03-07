// filepath: rtl/spi/axi_spi.sv
// AXI4-Lite SPI Master Periferal Wrapper
// axi_lite_slave generic bridge üzerinden register R/W arayüzü.
// SPI Master Core ile tam duplex 8-bit transferler.
//
// ┌─────────────────────────────────────────────────────────────┐
// │  Register Map (Offset from SPI_BASE = 0x4000_0100)         │
// ├────────┬────────────┬──────┬────────────────────────────────┤
// │ Offset │ Name       │ R/W  │ Description                    │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x00   │ TXDATA     │  W   │ [7:0] Gönderilecek byte        │
// │        │            │  R   │ [7:0] Son yazılan TXDATA        │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x04   │ RXDATA     │  R   │ [7:0] Son alınan byte           │
// │        │            │  W   │ yazma etkisiz                   │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x08   │ STATUS     │  R   │ [0] busy (transfer devam ediyor)│
// │        │            │      │ [1] rx_valid (yeni veri geldi)  │
// │        │            │      │ [2] ready (transfer kabul eder) │
// │        │            │  W   │ Herhangi bir yazma → rx_valid   │
// │        │            │      │   bayrağını temizler             │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x0C   │ CTRL       │ R/W  │ [0] en (modül etkin)           │
// │        │            │      │ [1] cpol (clock polarity)       │
// │        │            │      │ [2] cpha (clock phase)          │
// │        │            │      │ [3] ie (interrupt enable)       │
// │        │            │      │ [5:4] cs_sel (slave seçimi 0–3) │
// │        │            │      │ [6] cs_en (chip select assert)  │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x10   │ CLK_DIV    │ R/W  │ [7:0] SCK clock divider        │
// │        │            │      │ SCK half-period = (CLK_DIV+1)   │
// │        │            │      │ system clk cycle                │
// │        │            │      │ SCK freq = clk/(2*(CLK_DIV+1))  │
// │        │            │      │ 100MHz→1MHz: CLK_DIV=49         │
// │        │            │      │ 100MHz→10MHz: CLK_DIV=4         │
// ├────────┼────────────┼──────┼────────────────────────────────┤
// │ 0x14   │ CMD        │  W   │ [0] start — yazma anında        │
// │        │            │      │   1-cycle transfer pulse üretir  │
// │        │            │  R   │ 0x00000000                      │
// └────────┴────────────┴──────┴────────────────────────────────┘
//
// Kullanım sırası (yazılımdan):
//   1. CLK_DIV ← istenen SCK hızı
//   2. CTRL ← {cs_en, cs_sel, ie, cpha, cpol, en}
//   3. TXDATA ← gönderilecek byte
//   4. CMD ← 0x01 (start) → transfer başlar
//   5. STATUS.busy=0 bekle → RXDATA oku
//
// Interrupt: irq = ie & rx_valid
`timescale 1ns / 1ps

module axi_spi
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH      = AXI_ADDR_WIDTH,
  parameter int DATA_WIDTH      = AXI_DATA_WIDTH,
  parameter int DEFAULT_CLK_DIV = 8'd49   // 100 MHz / (2*50) = 1 MHz SCK
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

  // ── SPI fiziksel hatlar ─────────────────────────
  output logic                        sck_o,
  output logic                        mosi_o,
  input  logic                        miso_i,
  output logic [3:0]                  ss_o,

  // ── Interrupt çıkışı ───────────────────────────
  output logic                        irq_o
);

  // ════════════════════════════════════════════════
  // Register offset tanımları
  // ════════════════════════════════════════════════
  localparam logic [7:0] REG_TXDATA  = 8'h00;
  localparam logic [7:0] REG_RXDATA  = 8'h04;
  localparam logic [7:0] REG_STATUS  = 8'h08;
  localparam logic [7:0] REG_CTRL    = 8'h0C;
  localparam logic [7:0] REG_CLK_DIV = 8'h10;
  localparam logic [7:0] REG_CMD     = 8'h14;

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
  logic [31:0] ctrl_q;        // CTRL register
  logic [7:0]  clk_div_q;     // CLK_DIV register
  logic [7:0]  txdata_q;      // Son yazılan TX data

  // CTRL alanları
  wire        spi_en   = ctrl_q[0];
  wire        spi_cpol = ctrl_q[1];
  wire        spi_cpha = ctrl_q[2];
  wire        spi_ie   = ctrl_q[3];
  wire [1:0]  spi_cs_sel = ctrl_q[5:4];
  wire        spi_cs_en  = ctrl_q[6];

  // ════════════════════════════════════════════════
  // SPI Master Core sinyalleri
  // ════════════════════════════════════════════════
  logic        core_start;
  logic        core_ready;
  logic [7:0]  core_rx_data;
  logic        core_rx_valid;

  // rx_valid latch — STATUS okunana veya temizlenene kadar tutulan bayrak
  logic        rx_valid_latch_q;
  logic [7:0]  rx_data_q;

  // ════════════════════════════════════════════════
  // SPI Master Core Örneği
  // ════════════════════════════════════════════════
  spi_master u_spi_master (
    .clk_i      (clk_i),
    .rstn_i     (rstn_i),
    .en_i       (spi_en),
    .clk_div_i  (clk_div_q),
    .cpol_i     (spi_cpol),
    .cpha_i     (spi_cpha),
    .start_i    (core_start),
    .ready_o    (core_ready),
    .tx_data_i  (txdata_q),
    .rx_data_o  (core_rx_data),
    .rx_valid_o (core_rx_valid),
    .cs_sel_i   (spi_cs_sel),
    .cs_en_i    (spi_cs_en),
    .sck_o      (sck_o),
    .mosi_o     (mosi_o),
    .miso_i     (miso_i),
    .ss_o       (ss_o)
  );

  // ════════════════════════════════════════════════
  // CMD Tetikleme — CMD register'a yazıldığında start pulse
  // ════════════════════════════════════════════════
  logic cmd_trigger_q;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      cmd_trigger_q <= 1'b0;
    end else begin
      cmd_trigger_q <= 1'b0;  // default: temizle
      if (reg_wr_en && (reg_addr == REG_CMD) && reg_wdata[0]) begin
        cmd_trigger_q <= 1'b1;
      end
    end
  end

  assign core_start = cmd_trigger_q;

  // ════════════════════════════════════════════════
  // RX Data Latch & rx_valid sticky
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      rx_data_q        <= 8'd0;
      rx_valid_latch_q <= 1'b0;
    end else begin
      // Yeni RX verisi geldiğinde latch'le
      if (core_rx_valid) begin
        rx_data_q        <= core_rx_data;
        rx_valid_latch_q <= 1'b1;
      end
      // STATUS register'a yazma → rx_valid temizle
      if (reg_wr_en && (reg_addr == REG_STATUS)) begin
        rx_valid_latch_q <= 1'b0;
      end
    end
  end

  // ════════════════════════════════════════════════
  // Register Write Logic
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      ctrl_q    <= 32'd0;
      clk_div_q <= DEFAULT_CLK_DIV;
      txdata_q  <= 8'd0;
    end else if (reg_wr_en) begin
      case (reg_addr)
        REG_TXDATA:  txdata_q  <= reg_wdata[7:0];
        REG_CTRL:    ctrl_q    <= reg_wdata;
        REG_CLK_DIV: clk_div_q <= reg_wdata[7:0];
        // CMD yazma → cmd_trigger yukarıda
        // STATUS yazma → rx_valid clear yukarıda
        default: ;
      endcase
    end
  end

  // ════════════════════════════════════════════════
  // Register Read MUX
  // ════════════════════════════════════════════════
  always_comb begin
    case (reg_addr)
      REG_TXDATA:  reg_rdata = {24'd0, txdata_q};
      REG_RXDATA:  reg_rdata = {24'd0, rx_data_q};
      REG_STATUS:  reg_rdata = {29'd0, core_ready,         // [2] ready
                                       rx_valid_latch_q,   // [1] rx_valid
                                       (spi_en & ~core_ready)};  // [0] busy (only when enabled)
      REG_CTRL:    reg_rdata = ctrl_q;
      REG_CLK_DIV: reg_rdata = {24'd0, clk_div_q};
      REG_CMD:     reg_rdata = 32'd0;
      default:     reg_rdata = 32'd0;
    endcase
  end

  // ════════════════════════════════════════════════
  // Interrupt Logic
  // irq = ie & rx_valid
  // ════════════════════════════════════════════════
  assign irq_o = spi_ie & rx_valid_latch_q;

endmodule
