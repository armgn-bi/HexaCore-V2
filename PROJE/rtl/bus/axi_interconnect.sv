// filepath: rtl/bus/axi_interconnect.sv
// AXI4-Lite Interconnect — 1 Master, N Slave
// Adres decoder ile master'ın AW/AR adresine göre ilgili slave'i seçer.
// Tek master olduğu için arbitration gerekmez; sadece adres-tabanlı yönlendirme yapar.
`timescale 1ns / 1ps

module axi_interconnect
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH = AXI_ADDR_WIDTH,
  parameter int DATA_WIDTH = AXI_DATA_WIDTH,
  parameter int N_SLAVES   = NUM_SLAVES
)(
  input  logic clk_i,
  input  logic rstn_i,

  // ══════════════════════════════════════════════
  // Master portları (AXI Master IF'den gelir)
  // ══════════════════════════════════════════════
  // Write Address
  input  logic [ADDR_WIDTH-1:0]   m_awaddr_i,
  input  logic [2:0]              m_awprot_i,
  input  logic                    m_awvalid_i,
  output logic                    m_awready_o,

  // Write Data
  input  logic [DATA_WIDTH-1:0]   m_wdata_i,
  input  logic [DATA_WIDTH/8-1:0] m_wstrb_i,
  input  logic                    m_wvalid_i,
  output logic                    m_wready_o,

  // Write Response
  output logic [1:0]              m_bresp_o,
  output logic                    m_bvalid_o,
  input  logic                    m_bready_i,

  // Read Address
  input  logic [ADDR_WIDTH-1:0]   m_araddr_i,
  input  logic [2:0]              m_arprot_i,
  input  logic                    m_arvalid_i,
  output logic                    m_arready_o,

  // Read Data
  output logic [DATA_WIDTH-1:0]   m_rdata_o,
  output logic [1:0]              m_rresp_o,
  output logic                    m_rvalid_o,
  input  logic                    m_rready_i,

  // ══════════════════════════════════════════════
  // Slave portları (flat array — her slave için ayrı sinyal grubu)
  // ══════════════════════════════════════════════
  // Write Address
  output logic [ADDR_WIDTH-1:0]   s_awaddr_o  [N_SLAVES],
  output logic [2:0]              s_awprot_o  [N_SLAVES],
  output logic                    s_awvalid_o [N_SLAVES],
  input  logic                    s_awready_i [N_SLAVES],

  // Write Data
  output logic [DATA_WIDTH-1:0]   s_wdata_o   [N_SLAVES],
  output logic [DATA_WIDTH/8-1:0] s_wstrb_o   [N_SLAVES],
  output logic                    s_wvalid_o  [N_SLAVES],
  input  logic                    s_wready_i  [N_SLAVES],

  // Write Response
  input  logic [1:0]              s_bresp_i   [N_SLAVES],
  input  logic                    s_bvalid_i  [N_SLAVES],
  output logic                    s_bready_o  [N_SLAVES],

  // Read Address
  output logic [ADDR_WIDTH-1:0]   s_araddr_o  [N_SLAVES],
  output logic [2:0]              s_arprot_o  [N_SLAVES],
  output logic                    s_arvalid_o [N_SLAVES],
  input  logic                    s_arready_i [N_SLAVES],

  // Read Data
  input  logic [DATA_WIDTH-1:0]   s_rdata_i   [N_SLAVES],
  input  logic [1:0]              s_rresp_i   [N_SLAVES],
  input  logic                    s_rvalid_i  [N_SLAVES],
  output logic                    s_rready_o  [N_SLAVES]
);

  // ════════════════════════════════════════════════
  // Adres Decoder Fonksiyonu
  // addr & ~MASK == BASE  →  eşleşme
  // ════════════════════════════════════════════════
  function automatic logic [N_SLAVES-1:0] decode_addr(
    input logic [ADDR_WIDTH-1:0] addr
  );
    logic [N_SLAVES-1:0] sel;
    sel = '0;
    for (int i = 0; i < N_SLAVES; i++) begin
      if ((addr & ~SLV_MASK[i]) == SLV_BASE[i])
        sel[i] = 1'b1;
    end
    return sel;
  endfunction

  // ════════════════════════════════════════════════
  // Yazma kanalı slave seçimi
  // AW adresi geldiğinde hangi slave'e gideceğini belirle ve kilitle
  // ════════════════════════════════════════════════
  logic [N_SLAVES-1:0] wr_sel;     // combinational decode
  logic [N_SLAVES-1:0] wr_sel_q;   // latch'lenmiş (transaction boyunca sabit)
  logic                wr_active_q;

  assign wr_sel = decode_addr(m_awaddr_i);

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      wr_sel_q    <= '0;
      wr_active_q <= 1'b0;
    end else begin
      if (!wr_active_q && m_awvalid_i) begin
        wr_sel_q    <= wr_sel;
        wr_active_q <= 1'b1;
      end
      // B handshake tamamlandığında serbest bırak
      if (wr_active_q && m_bvalid_o && m_bready_i) begin
        wr_active_q <= 1'b0;
      end
    end
  end

  wire [N_SLAVES-1:0] wr_target = wr_active_q ? wr_sel_q : wr_sel;

  // Hiçbir slave eşleşmezse decode error döndürmek için
  wire wr_no_match = (wr_target == '0);

  // ════════════════════════════════════════════════
  // Okuma kanalı slave seçimi
  // ════════════════════════════════════════════════
  logic [N_SLAVES-1:0] rd_sel;
  logic [N_SLAVES-1:0] rd_sel_q;
  logic                rd_active_q;

  assign rd_sel = decode_addr(m_araddr_i);

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      rd_sel_q    <= '0;
      rd_active_q <= 1'b0;
    end else begin
      if (!rd_active_q && m_arvalid_i) begin
        rd_sel_q    <= rd_sel;
        rd_active_q <= 1'b1;
      end
      if (rd_active_q && m_rvalid_o && m_rready_i) begin
        rd_active_q <= 1'b0;
      end
    end
  end

  wire [N_SLAVES-1:0] rd_target = rd_active_q ? rd_sel_q : rd_sel;
  wire rd_no_match = (rd_target == '0);

  // ════════════════════════════════════════════════
  // Master → Slave yönlendirme (broadcast + gating)
  // ════════════════════════════════════════════════
  always_comb begin
    for (int i = 0; i < N_SLAVES; i++) begin
      // Write Address
      s_awaddr_o [i] = m_awaddr_i;
      s_awprot_o [i] = m_awprot_i;
      s_awvalid_o[i] = m_awvalid_i && wr_target[i];

      // Write Data
      s_wdata_o [i]  = m_wdata_i;
      s_wstrb_o [i]  = m_wstrb_i;
      s_wvalid_o[i]  = m_wvalid_i && wr_target[i];

      // Write Response — sadece seçili slave'in bready'sini ilet
      s_bready_o[i]  = m_bready_i && wr_target[i];

      // Read Address
      s_araddr_o [i] = m_araddr_i;
      s_arprot_o [i] = m_arprot_i;
      s_arvalid_o[i] = m_arvalid_i && rd_target[i];

      // Read Data — sadece seçili slave'in rready'sini ilet
      s_rready_o[i]  = m_rready_i && rd_target[i];
    end
  end

  // ════════════════════════════════════════════════
  // Slave → Master MUX (seçili slave'in yanıtını master'a ilet)
  // ════════════════════════════════════════════════

  // ── Yazma kanalı MUX ────────────────────────────
  always_comb begin
    m_awready_o = 1'b0;
    m_wready_o  = 1'b0;
    m_bresp_o   = AXI_RESP_DECERR;
    m_bvalid_o  = 1'b0;

    if (wr_no_match) begin
      // Hiçbir slave eşleşmedi — decode error yanıtı.
      // AW ve W'yi hemen kabul et, DECERR ile B yanıtı ver.
      m_awready_o = 1'b1;
      m_wready_o  = 1'b1;
      m_bresp_o   = AXI_RESP_DECERR;
      m_bvalid_o  = m_awvalid_i || m_wvalid_i;
    end else begin
      for (int i = 0; i < N_SLAVES; i++) begin
        if (wr_target[i]) begin
          m_awready_o = s_awready_i[i];
          m_wready_o  = s_wready_i [i];
          m_bresp_o   = s_bresp_i  [i];
          m_bvalid_o  = s_bvalid_i [i];
        end
      end
    end
  end

  // ── Okuma kanalı MUX ───────────────────────────
  always_comb begin
    m_arready_o = 1'b0;
    m_rdata_o   = '0;
    m_rresp_o   = AXI_RESP_DECERR;
    m_rvalid_o  = 1'b0;

    if (rd_no_match) begin
      m_arready_o = 1'b1;
      m_rdata_o   = 32'hDEAD_BEEF;
      m_rresp_o   = AXI_RESP_DECERR;
      m_rvalid_o  = m_arvalid_i;
    end else begin
      for (int i = 0; i < N_SLAVES; i++) begin
        if (rd_target[i]) begin
          m_arready_o = s_arready_i[i];
          m_rdata_o   = s_rdata_i  [i];
          m_rresp_o   = s_rresp_i  [i];
          m_rvalid_o  = s_rvalid_i [i];
        end
      end
    end
  end

endmodule
