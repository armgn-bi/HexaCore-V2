// filepath: rtl/bus/axi_master_if.sv
// RISC-V Core MEM-stage → AXI4-Lite Master Bridge
// Pipeline'ın mem_read / mem_write / mem_size sinyallerini AXI4-Lite
// handshake protokolüne dönüştürür. Transaction bitene kadar pipeline'ı stall eder.
`timescale 1ns / 1ps

module axi_master_if
  import riscv_pkg::*;
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH = AXI_ADDR_WIDTH,
  parameter int DATA_WIDTH = AXI_DATA_WIDTH
)(
  input  logic                    clk_i,
  input  logic                    rstn_i,

  // ── Pipeline MEM-stage arayüzü ──────────────────
  input  logic                    mem_read_i,      // LB/LH/LW/LBU/LHU
  input  logic                    mem_write_i,     // SB/SH/SW
  input  logic [1:0]              mem_size_i,      // 00=byte, 01=half, 10=word
  input  logic                    mem_unsigned_i,  // unsigned load flag (bridge tarafından kullanılmaz, SoC'de sign-extend yapılır)
  input  logic [ADDR_WIDTH-1:0]   addr_i,          // aluY_M (hedef adres)
  input  logic [DATA_WIDTH-1:0]   wdata_i,         // storeDataM
  output logic [DATA_WIDTH-1:0]   rdata_o,         // readDataM karşılığı
  output logic                    ready_o,         // 1 = transaction tamamlandı veya idle, 0 = bekle (stall)

  // ── AXI4-Lite Master portları (flat sinyal) ─────
  // Write Address Channel
  output logic [ADDR_WIDTH-1:0]   m_axi_awaddr_o,
  output logic [2:0]              m_axi_awprot_o,
  output logic                    m_axi_awvalid_o,
  input  logic                    m_axi_awready_i,

  // Write Data Channel
  output logic [DATA_WIDTH-1:0]   m_axi_wdata_o,
  output logic [DATA_WIDTH/8-1:0] m_axi_wstrb_o,
  output logic                    m_axi_wvalid_o,
  input  logic                    m_axi_wready_i,

  // Write Response Channel
  input  logic [1:0]              m_axi_bresp_i,
  input  logic                    m_axi_bvalid_i,
  output logic                    m_axi_bready_o,

  // Read Address Channel
  output logic [ADDR_WIDTH-1:0]   m_axi_araddr_o,
  output logic [2:0]              m_axi_arprot_o,
  output logic                    m_axi_arvalid_o,
  input  logic                    m_axi_arready_i,

  // Read Data Channel
  input  logic [DATA_WIDTH-1:0]   m_axi_rdata_i,
  input  logic [1:0]              m_axi_rresp_i,
  input  logic                    m_axi_rvalid_i,
  output logic                    m_axi_rready_o
);

  // ════════════════════════════════════════════════
  // FSM States
  // ════════════════════════════════════════════════
  typedef enum logic [2:0] {
    S_IDLE,
    S_RD_ADDR,   // AR kanalı handshake bekle
    S_RD_DATA,   // R  kanalı handshake bekle
    S_WR_ADDR,   // AW kanalı handshake bekle
    S_WR_DATA,   // W  kanalı handshake bekle
    S_WR_RESP    // B  kanalı handshake bekle
  } state_t;

  state_t state_q, state_d;

  // Latched request sinyalleri (IDLE'da yakalanır)
  logic [ADDR_WIDTH-1:0]   addr_q;
  logic [DATA_WIDTH-1:0]   wdata_q;
  logic [DATA_WIDTH/8-1:0] wstrb_q;
  logic [DATA_WIDTH-1:0]   rdata_q;
  logic                    aw_done_q;   // AW/W paralel handshake izlemesi
  logic                    w_done_q;

  // ════════════════════════════════════════════════
  // Write Strobe üreteci (mem_size + addr[1:0])
  // ════════════════════════════════════════════════
  function automatic logic [3:0] gen_wstrb(
    input logic [1:0] size,
    input logic [1:0] byte_off
  );
    unique case (size)
      2'b00:   gen_wstrb = 4'b0001 << byte_off;           // SB
      2'b01:   gen_wstrb = 4'b0011 << byte_off;           // SH
      default: gen_wstrb = 4'b1111;                        // SW
    endcase
  endfunction

  // ════════════════════════════════════════════════
  // FSM — sequential
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      state_q   <= S_IDLE;
      addr_q    <= '0;
      wdata_q   <= '0;
      wstrb_q   <= '0;
      rdata_q   <= '0;
      aw_done_q <= 1'b0;
      w_done_q  <= 1'b0;
    end else begin
      state_q <= state_d;

      unique case (state_q)
        // ── IDLE: yeni istek varsa yakala ──
        S_IDLE: begin
          aw_done_q <= 1'b0;
          w_done_q  <= 1'b0;
          if (mem_read_i || mem_write_i) begin
            addr_q  <= addr_i;
            wdata_q <= wdata_i;
            wstrb_q <= gen_wstrb(mem_size_i, addr_i[1:0]);
          end
        end

        // ── WRITE: AW ve W paralel ilerleyebilir ──
        S_WR_ADDR: begin
          if (m_axi_awvalid_o && m_axi_awready_i)
            aw_done_q <= 1'b1;
          if (m_axi_wvalid_o && m_axi_wready_i)
            w_done_q <= 1'b1;
        end

        S_WR_DATA: begin
          if (m_axi_wvalid_o && m_axi_wready_i)
            w_done_q <= 1'b1;
        end

        // ── READ: R kanalından veri yakala ──
        S_RD_DATA: begin
          if (m_axi_rvalid_i && m_axi_rready_o)
            rdata_q <= m_axi_rdata_i;
        end

        default: ;
      endcase
    end
  end
  // AW/W paralel handshake sinyalleri (always_comb içinde kullanılır)
  logic aw_fire;
  logic w_fire;

  // ════════════════════════════════════════════════
  // FSM — combinational next-state + outputs
  // ════════════════════════════════════════════════
  always_comb begin
    // Varsayılan değerler
    state_d          = state_q;
    ready_o          = 1'b0;

    aw_fire          = 1'b0;
    w_fire           = 1'b0;

    m_axi_awaddr_o   = addr_q;
    m_axi_awprot_o   = 3'b000;
    m_axi_awvalid_o  = 1'b0;

    m_axi_wdata_o    = wdata_q;
    m_axi_wstrb_o    = wstrb_q;
    m_axi_wvalid_o   = 1'b0;

    m_axi_bready_o   = 1'b0;

    m_axi_araddr_o   = addr_q;
    m_axi_arprot_o   = 3'b000;
    m_axi_arvalid_o  = 1'b0;

    m_axi_rready_o   = 1'b0;

    rdata_o          = rdata_q;    unique case (state_q)
      // ────────────────────── IDLE ──────────────────────
      S_IDLE: begin
        if (mem_read_i) begin
          ready_o = 1'b0;   // yeni istek var — pipeline'ı durdur
          state_d = S_RD_ADDR;
        end else if (mem_write_i) begin
          ready_o = 1'b0;
          state_d = S_WR_ADDR;
        end else begin
          ready_o = 1'b1;   // boşta — pipeline ilerleyebilir
        end
      end

      // ────────────────────── READ ─────────────────────
      S_RD_ADDR: begin
        m_axi_arvalid_o = 1'b1;
        if (m_axi_arready_i)
          state_d = S_RD_DATA;
      end

      S_RD_DATA: begin
        m_axi_rready_o = 1'b1;
        if (m_axi_rvalid_i) begin
          state_d = S_IDLE;
          rdata_o = m_axi_rdata_i;   // combinational bypass — aynı cycle'da pipeline'a ver
        end
      end

      // ────────────────────── WRITE ────────────────────
      // AW ve W kanallarını aynı anda sürüyoruz.
      // Hangisi önce kabul edilirse o "done" olur; ikisi de bitince RESP'e geçeriz.
      S_WR_ADDR: begin
        m_axi_awvalid_o = !aw_done_q;
        m_axi_wvalid_o  = !w_done_q;

        // Her iki handshake tamamlandı mı?
        aw_fire = aw_done_q || (m_axi_awvalid_o && m_axi_awready_i);
        w_fire  = w_done_q  || (m_axi_wvalid_o  && m_axi_wready_i);

        if (aw_fire && w_fire)
          state_d = S_WR_RESP;
        else if (aw_fire && !w_fire)
          state_d = S_WR_DATA;   // sadece W bekle
        // else: AW veya her ikisi hâlâ bekliyor — kal
      end

      S_WR_DATA: begin
        m_axi_wvalid_o = 1'b1;
        if (m_axi_wready_i)
          state_d = S_WR_RESP;
      end

      S_WR_RESP: begin
        m_axi_bready_o = 1'b1;
        if (m_axi_bvalid_i)
          state_d = S_IDLE;
      end

      default: state_d = S_IDLE;
    endcase
  end

endmodule
