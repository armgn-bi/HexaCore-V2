// filepath: rtl/bus/axi_lite_slave.sv
// Genel amaçlı AXI4-Lite Slave arayüzü
// Periferaller (UART, SPI, I2C, DSP vb.) bu modülü kullanarak
// AXI4-Lite protokolünü basit register read/write arayüzüne dönüştürür.
`timescale 1ns / 1ps

module axi_lite_slave
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH = AXI_ADDR_WIDTH,
  parameter int DATA_WIDTH = AXI_DATA_WIDTH,
  parameter int REG_ADDR_WIDTH = 8   // Periferal iç adres genişliği (offset bitleri)
)(
  input  logic                        clk_i,
  input  logic                        rstn_i,

  // ── AXI4-Lite Slave portları ────────────────────
  // Write Address
  input  logic [ADDR_WIDTH-1:0]       s_axi_awaddr_i,
  input  logic [2:0]                  s_axi_awprot_i,
  input  logic                        s_axi_awvalid_i,
  output logic                        s_axi_awready_o,

  // Write Data
  input  logic [DATA_WIDTH-1:0]       s_axi_wdata_i,
  input  logic [DATA_WIDTH/8-1:0]     s_axi_wstrb_i,
  input  logic                        s_axi_wvalid_i,
  output logic                        s_axi_wready_o,

  // Write Response
  output logic [1:0]                  s_axi_bresp_o,
  output logic                        s_axi_bvalid_o,
  input  logic                        s_axi_bready_i,

  // Read Address
  input  logic [ADDR_WIDTH-1:0]       s_axi_araddr_i,
  input  logic [2:0]                  s_axi_arprot_i,
  input  logic                        s_axi_arvalid_i,
  output logic                        s_axi_arready_o,

  // Read Data
  output logic [DATA_WIDTH-1:0]       s_axi_rdata_o,
  output logic [1:0]                  s_axi_rresp_o,
  output logic                        s_axi_rvalid_o,
  input  logic                        s_axi_rready_i,

  // ── Periferal basit register arayüzü ────────────
  output logic                        reg_wr_en_o,
  output logic                        reg_rd_en_o,
  output logic [REG_ADDR_WIDTH-1:0]   reg_addr_o,
  output logic [DATA_WIDTH-1:0]       reg_wdata_o,
  output logic [DATA_WIDTH/8-1:0]     reg_wstrb_o,
  input  logic [DATA_WIDTH-1:0]       reg_rdata_i
);

  // ════════════════════════════════════════════════
  // İç durum
  // ════════════════════════════════════════════════
  // AW ve W kanalları bağımsız gelebilir; ikisini de yakaladıktan sonra
  // periferal'e yazma uygula, sonra B yanıtı ver.
  logic aw_ready_q, w_ready_q;
  logic [ADDR_WIDTH-1:0] awaddr_q;
  logic [DATA_WIDTH-1:0] wdata_q;
  logic [DATA_WIDTH/8-1:0] wstrb_q;

  logic ar_ready_q;
  logic [ADDR_WIDTH-1:0] araddr_q;

  logic bvalid_q;
  logic rvalid_q;
  logic [DATA_WIDTH-1:0] rdata_q;

  // ════════════════════════════════════════════════
  // Write Address Channel
  // ════════════════════════════════════════════════
  assign s_axi_awready_o = aw_ready_q;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      aw_ready_q <= 1'b1;   // Başlangıçta kabul etmeye hazır
      awaddr_q   <= '0;
    end else begin
      if (aw_ready_q && s_axi_awvalid_i) begin
        aw_ready_q <= 1'b0;   // Adresi aldık, artık hazır değiliz
        awaddr_q   <= s_axi_awaddr_i;
      end
      // Yazma yanıtı teslim edildiğinde tekrar hazır ol
      if (bvalid_q && s_axi_bready_i)
        aw_ready_q <= 1'b1;
    end
  end

  // ════════════════════════════════════════════════
  // Write Data Channel
  // ════════════════════════════════════════════════
  assign s_axi_wready_o = w_ready_q;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      w_ready_q <= 1'b1;
      wdata_q   <= '0;
      wstrb_q   <= '0;
    end else begin
      if (w_ready_q && s_axi_wvalid_i) begin
        w_ready_q <= 1'b0;
        wdata_q   <= s_axi_wdata_i;
        wstrb_q   <= s_axi_wstrb_i;
      end
      if (bvalid_q && s_axi_bready_i)
        w_ready_q <= 1'b1;
    end
  end

  // ════════════════════════════════════════════════
  // Periferal yazma tetiklemesi
  // ════════════════════════════════════════════════
  // Her iki kanal da alındığında (ready→0 olmuşsa) ve henüz B gönderilmemişse yaz
  wire wr_fire = (!aw_ready_q) && (!w_ready_q) && (!bvalid_q);

  assign reg_wr_en_o = wr_fire;
  assign reg_wdata_o = wdata_q;
  assign reg_wstrb_o = wstrb_q;

  // ════════════════════════════════════════════════
  // Write Response Channel
  // ════════════════════════════════════════════════
  assign s_axi_bresp_o  = AXI_RESP_OKAY;
  assign s_axi_bvalid_o = bvalid_q;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i)
      bvalid_q <= 1'b0;
    else begin
      if (wr_fire)
        bvalid_q <= 1'b1;
      else if (bvalid_q && s_axi_bready_i)
        bvalid_q <= 1'b0;
    end
  end

  // ════════════════════════════════════════════════
  // Read Address Channel
  // ════════════════════════════════════════════════
  assign s_axi_arready_o = ar_ready_q;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      ar_ready_q <= 1'b1;
      araddr_q   <= '0;
    end else begin
      if (ar_ready_q && s_axi_arvalid_i) begin
        ar_ready_q <= 1'b0;
        araddr_q   <= s_axi_araddr_i;
      end
      if (rvalid_q && s_axi_rready_i)
        ar_ready_q <= 1'b1;
    end
  end

  // ════════════════════════════════════════════════
  // Periferal okuma tetiklemesi
  // ════════════════════════════════════════════════
  wire rd_fire = (!ar_ready_q) && (!rvalid_q);

  assign reg_rd_en_o = rd_fire;

  // ════════════════════════════════════════════════
  // Read Data Channel
  // ════════════════════════════════════════════════
  assign s_axi_rdata_o  = rdata_q;
  assign s_axi_rresp_o  = AXI_RESP_OKAY;
  assign s_axi_rvalid_o = rvalid_q;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      rvalid_q <= 1'b0;
      rdata_q  <= '0;
    end else begin
      if (rd_fire) begin
        rvalid_q <= 1'b1;
        rdata_q  <= reg_rdata_i;
      end else if (rvalid_q && s_axi_rready_i) begin
        rvalid_q <= 1'b0;
      end
    end
  end

  // ════════════════════════════════════════════════
  // Adres çıkışı — periferal her iki işlemde de offset olarak görür
  // ════════════════════════════════════════════════
  // Yazma adresi (wr_fire anında) veya okuma adresi (rd_fire anında)
  always_comb begin
    if (wr_fire)
      reg_addr_o = awaddr_q[REG_ADDR_WIDTH-1:0];
    else
      reg_addr_o = araddr_q[REG_ADDR_WIDTH-1:0];
  end

endmodule
