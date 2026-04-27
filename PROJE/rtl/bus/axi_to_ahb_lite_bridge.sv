// filepath: rtl/bus/axi_to_ahb_lite_bridge.sv
// AXI4-Lite to AHB-Lite Bridge
// AXI4-Lite slave interface'ten AHB-Lite master interface'e dönüşüm
`timescale 1ns / 1ps

module axi_to_ahb_lite_bridge
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH = AXI_ADDR_WIDTH,
  parameter int DATA_WIDTH = AXI_DATA_WIDTH
)(
  input  logic                        clk_i,
  input  logic                        rstn_i,

  // ════════════════════════════════════════════════
  // AXI4-Lite Slave Interface
  // ════════════════════════════════════════════════
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

  // ════════════════════════════════════════════════
  // AHB-Lite Master Interface
  // ════════════════════════════════════════════════
  output logic                        ahb_hsel_o,
  output logic [1:0]                  ahb_htrans_o,
  output logic                        ahb_hwrite_o,
  output logic                        ahb_hmastlock_o,
  output logic [2:0]                  ahb_hsize_o,
  output logic [2:0]                  ahb_hburst_o,
  output logic [3:0]                  ahb_hprot_o,
  output logic [ADDR_WIDTH-1:0]       ahb_haddr_o,
  output logic [DATA_WIDTH-1:0]       ahb_hwdata_o,
  output logic                        ahb_hready_o,
  input  logic                        ahb_hready_i,
  output logic [DATA_WIDTH-1:0]       ahb_hrdata_o,
  output logic                        ahb_hresp_o
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
  // WSTRB to HSIZE conversion
  // ════════════════════════════════════════════════
  function automatic logic [2:0] wstrb_to_hsize(input logic [3:0] wstrb, input logic [1:0] addr_lsb);
    case (wstrb)
      4'b0001, 4'b0010, 4'b0100, 4'b1000: return 3'b000;  // Byte
      4'b0011, 4'b1100: return 3'b001;  // Halfword
      4'b1111: return 3'b010;  // Word
      default: return 3'b000;
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
          if (s_axi_awvalid_i) begin
            state_q   <= S_WRITE_ADDR;
            addr_reg  <= s_axi_awaddr_i;
            wdata_reg <= s_axi_wdata_i;
            wstrb_reg <= s_axi_wstrb_i;
          end else if (s_axi_arvalid_i) begin
            state_q  <= S_READ_ADDR;
            addr_reg <= s_axi_araddr_i;
          end
        end

        S_WRITE_ADDR: begin
          if (ahb_hready_i) begin
            state_q <= S_WRITE_DATA;
          end
        end

        S_WRITE_DATA: begin
          if (ahb_hready_i) begin
            state_q <= S_WRITE_RESP;
          end
        end

        S_WRITE_RESP: begin
          if (s_axi_bready_i) begin
            state_q <= S_IDLE;
          end
        end

        S_READ_ADDR: begin
          if (ahb_hready_i) begin
            state_q <= S_READ_DATA;
          end
        end

        S_READ_DATA: begin
          if (s_axi_rready_i) begin
            rdata_reg <= ahb_hrdata_o;
            rresp_reg <= {1'b0, ahb_hresp_o};
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
  assign s_axi_awready_o = (state_q == S_WRITE_ADDR);
  assign s_axi_wready_o  = (state_q == S_WRITE_DATA);
  assign s_axi_bresp_o   = AXI_RESP_OKAY;
  assign s_axi_bvalid_o  = (state_q == S_WRITE_RESP);
  assign s_axi_arready_o = (state_q == S_READ_ADDR);
  assign s_axi_rdata_o   = rdata_reg;
  assign s_axi_rresp_o   = rresp_reg;
  assign s_axi_rvalid_o  = (state_q == S_READ_DATA);

  // ════════════════════════════════════════════════
  // AHB-Lite outputs
  // ════════════════════════════════════════════════
  assign ahb_hsel_o      = (state_q == S_WRITE_ADDR) || (state_q == S_READ_ADDR);
  assign ahb_htrans_o    = (state_q == S_WRITE_ADDR || state_q == S_READ_ADDR) ? 2'b10 : 2'b00;
  assign ahb_hwrite_o    = (state_q == S_WRITE_ADDR || state_q == S_WRITE_DATA);
  assign ahb_hmastlock_o = 1'b0;
  assign ahb_hsize_o     = wstrb_to_hsize(wstrb_reg, addr_reg[1:0]);
  assign ahb_hburst_o    = 3'b000;
  assign ahb_hprot_o     = 4'b0011;
  assign ahb_haddr_o     = addr_reg;
  assign ahb_hwdata_o    = wdata_reg;
  assign ahb_hready_o    = (state_q == S_WRITE_DATA) || (state_q == S_READ_DATA);
  assign ahb_hrdata_o    = ahb_hrdata_o;
  assign ahb_hresp_o     = 1'b0;

endmodule
