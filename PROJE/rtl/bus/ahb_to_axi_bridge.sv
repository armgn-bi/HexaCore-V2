// filepath: rtl/bus/ahb_to_axi_bridge.sv
// AHB-Lite to AXI4-Lite Bridge
// HexaChipsers-Core AHB-Lite slave'lerini mevcut projenin AXI4-Lite bus'una bağlar
//
// AHB-Lite → AXI4-Lite Mapping:
// - HSEL/HTRANS → AWVALID/ARVALID
// - HADDR → AWADDR/ARADDR
// - HWRITE → AWVALID/ARVALID selection
// - HWDATA → WDATA
// - HSIZE → AWSIZE/ARSIZE
// - HREADY → WREADY/RREADY
// - HRDATA → RDATA
// - HRESP → RRESP

`timescale 1ns / 1ps

module ahb_to_axi_bridge
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH = AXI_ADDR_WIDTH,
  parameter int DATA_WIDTH = AXI_DATA_WIDTH
)(
  input  logic                        clk_i,
  input  logic                        rstn_i,

  // ════════════════════════════════════════════════
  // AHB-Lite Slave Interface (from HexaChipsers-Core)
  // ════════════════════════════════════════════════
  input  logic                        ahb_hsel_i,
  input  logic [1:0]                  ahb_htrans_i,
  input  logic                        ahb_hwrite_i,
  input  logic [2:0]                  ahb_hsize_i,
  input  logic [2:0]                  ahb_hburst_i,
  input  logic [3:0]                  ahb_hprot_i,
  input  logic [ADDR_WIDTH-1:0]       ahb_haddr_i,
  input  logic [DATA_WIDTH-1:0]       ahb_hwdata_i,
  input  logic                        ahb_hready_i,
  output logic                        ahb_hready_o,
  output logic [DATA_WIDTH-1:0]       ahb_hrdata_o,
  output logic                        ahb_hresp_o,

  // ════════════════════════════════════════════════
  // AXI4-Lite Master Interface (to SoC bus)
  // ════════════════════════════════════════════════
  output logic [ADDR_WIDTH-1:0]       m_axi_awaddr_o,
  output logic [2:0]                  m_axi_awprot_o,
  output logic                        m_axi_awvalid_o,
  input  logic                        m_axi_awready_i,

  output logic [DATA_WIDTH-1:0]       m_axi_wdata_o,
  output logic [DATA_WIDTH/8-1:0]     m_axi_wstrb_o,
  output logic                        m_axi_wvalid_o,
  input  logic                        m_axi_wready_i,

  input  logic [1:0]                  m_axi_bresp_i,
  input  logic                        m_axi_bvalid_i,
  output logic                        m_axi_bready_o,

  output logic [ADDR_WIDTH-1:0]       m_axi_araddr_o,
  output logic [2:0]                  m_axi_arprot_o,
  output logic                        m_axi_arvalid_o,
  input  logic                        m_axi_arready_i,

  input  logic [DATA_WIDTH-1:0]       m_axi_rdata_i,
  input  logic [1:0]                  m_axi_rresp_i,
  input  logic                        m_axi_rvalid_i,
  output logic                        m_axi_rready_o
);

  // ════════════════════════════════════════════════
  // State machine
  // ════════════════════════════════════════════════
  typedef enum logic [2:0] {
    S_IDLE,
    S_WRITE_ADDR,
    S_WRITE_DATA,
    S_WRITE_RESP,
    S_READ_ADDR,
    S_READ_DATA
  } state_t;

  state_t state_q;

  // ════════════════════════════════════════════════
  // Internal registers
  // ════════════════════════════════════════════════
  logic [ADDR_WIDTH-1:0] addr_reg;
  logic [DATA_WIDTH-1:0] wdata_reg;
  logic [DATA_WIDTH/8-1:0] wstrb_reg;
  logic [DATA_WIDTH-1:0] rdata_reg;
  logic [1:0] rresp_reg;

  // ════════════════════════════════════════════════
  // HSIZE to WSTRB conversion
  // ════════════════════════════════════════════════
  function automatic logic [3:0] hsize_to_wstrb(input logic [2:0] hsize, input logic [1:0] haddr_lsb);
    case (hsize)
      3'b000: begin  // Byte
        case (haddr_lsb)
          2'b00: return 4'b0001;
          2'b01: return 4'b0010;
          2'b10: return 4'b0100;
          2'b11: return 4'b1000;
        endcase
      end
      3'b001: begin  // Halfword
        case (haddr_lsb[1])
          1'b0: return 4'b0011;
          1'b1: return 4'b1100;
        endcase
      end
      3'b010: return 4'b1111;  // Word
      default: return 4'b0000;
    endcase
  endfunction

  // ════════════════════════════════════════════════
  // State machine
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      state_q   <= S_IDLE;
      addr_reg  <= '0;
      wdata_reg <= '0;
      wstrb_reg <= '0;
      rdata_reg <= '0;
      rresp_reg <= '0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (ahb_hsel_i && ahb_htrans_i[1]) begin  // Non-SEQ or SEQ transfer
            if (ahb_hwrite_i) begin
              state_q   <= S_WRITE_ADDR;
              addr_reg  <= ahb_haddr_i;
              wdata_reg <= ahb_hwdata_i;
              wstrb_reg <= hsize_to_wstrb(ahb_hsize_i, ahb_haddr_i[1:0]);
            end else begin
              state_q  <= S_READ_ADDR;
              addr_reg <= ahb_haddr_i;
            end
          end
        end

        S_WRITE_ADDR: begin
          if (m_axi_awready_i) begin
            state_q <= S_WRITE_DATA;
          end
        end

        S_WRITE_DATA: begin
          if (m_axi_wready_i) begin
            state_q <= S_WRITE_RESP;
          end
        end

        S_WRITE_RESP: begin
          if (m_axi_bvalid_i) begin
            state_q <= S_IDLE;
          end
        end

        S_READ_ADDR: begin
          if (m_axi_arready_i) begin
            state_q <= S_READ_DATA;
          end
        end

        S_READ_DATA: begin
          if (m_axi_rvalid_i) begin
            rdata_reg <= m_axi_rdata_i;
            rresp_reg <= m_axi_rresp_i;
            state_q  <= S_IDLE;
          end
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

  // ════════════════════════════════════════════════
  // AXI4-Lite outputs
  // ════════════════════════════════════════════════
  assign m_axi_awaddr_o  = (state_q == S_WRITE_ADDR) ? addr_reg : '0;
  assign m_axi_awprot_o  = 3'b000;
  assign m_axi_awvalid_o = (state_q == S_WRITE_ADDR);

  assign m_axi_wdata_o   = (state_q == S_WRITE_DATA) ? wdata_reg : '0;
  assign m_axi_wstrb_o   = (state_q == S_WRITE_DATA) ? wstrb_reg : '0;
  assign m_axi_wvalid_o  = (state_q == S_WRITE_DATA);

  assign m_axi_bready_o  = (state_q == S_WRITE_RESP);

  assign m_axi_araddr_o  = (state_q == S_READ_ADDR) ? addr_reg : '0;
  assign m_axi_arprot_o  = 3'b000;
  assign m_axi_arvalid_o = (state_q == S_READ_ADDR);

  assign m_axi_rready_o  = (state_q == S_READ_DATA);

  // ════════════════════════════════════════════════
  // AHB-Lite outputs
  // ════════════════════════════════════════════════
  assign ahb_hready_o = (state_q == S_IDLE) ||
                        (state_q == S_WRITE_RESP && m_axi_bvalid_i) ||
                        (state_q == S_READ_DATA && m_axi_rvalid_i);

  assign ahb_hrdata_o = (state_q == S_READ_DATA && m_axi_rvalid_i) ? rdata_reg : '0;
  assign ahb_hresp_o  = (state_q == S_READ_DATA && m_axi_rvalid_i) ? rresp_reg[0] : 1'b0;

endmodule
