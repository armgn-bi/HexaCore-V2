// filepath: rtl/bus/axi_dmem_slave.sv
// DMEM için AXI4-Lite Slave Wrapper
// Mevcut dmem.sv modülünü AXI4-Lite arayüzüne sarar.
// dmem.sv'nin portlarına dokunmadan bir bridge görevi görür.
`timescale 1ns / 1ps

module axi_dmem_slave
  import riscv_pkg::*;
  import axi_pkg::*;
#(
  parameter int ADDR_WIDTH = AXI_ADDR_WIDTH,
  parameter int DATA_WIDTH = AXI_DATA_WIDTH,
  parameter string DMEM_INIT_FILE = "C:/Users/DELL/Downloads/HexaCore-V2/PROJE/dmem.mem",
  parameter logic [XLEN-1:0] DMEM_BASE = 32'h8001_0000,
  parameter int DMEM_BYTES = 32768
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

  // ── Debug arayüzü (opsiyonel, testbench için) ───
  input  logic [XLEN-1:0]            dbg_addr_i,
  output logic [XLEN-1:0]            dbg_data_o
);

  // ════════════════════════════════════════════════
  // İç sinyaller — dmem'e bağlanacak
  // ════════════════════════════════════════════════
  logic             mem_read;
  logic             mem_write;
  logic [1:0]       mem_size;
  logic             mem_unsigned;
  logic [XLEN-1:0]  mem_addr;
  logic [XLEN-1:0]  mem_wdata;
  logic [XLEN-1:0]  mem_rdata;

  // ════════════════════════════════════════════════
  // AXI FSM — basit 1-cycle yanıt (DMEM senkron)
  // ════════════════════════════════════════════════
  typedef enum logic [2:0] {
    ST_IDLE,
    ST_WR_EXEC,
    ST_WR_RESP,
    ST_RD_EXEC,
    ST_RD_RESP
  } state_t;

  state_t state_q;
  logic [ADDR_WIDTH-1:0] addr_q;
  logic [DATA_WIDTH-1:0] wdata_q;
  logic [DATA_WIDTH/8-1:0] wstrb_q;
  logic [DATA_WIDTH-1:0] rdata_q;

  // wstrb → mem_size dönüşümü
  function automatic logic [1:0] wstrb_to_size(input logic [3:0] strb);
    unique case (strb)
      4'b0001, 4'b0010, 4'b0100, 4'b1000: wstrb_to_size = 2'b00; // byte
      4'b0011, 4'b1100:                    wstrb_to_size = 2'b01; // half
      default:                              wstrb_to_size = 2'b10; // word
    endcase
  endfunction

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      state_q <= ST_IDLE;
      addr_q  <= '0;
      wdata_q <= '0;
      wstrb_q <= '0;
      rdata_q <= '0;
    end else begin
      unique case (state_q)
        ST_IDLE: begin
          if (s_axi_awvalid_i && s_axi_wvalid_i) begin
            addr_q  <= s_axi_awaddr_i;
            wdata_q <= s_axi_wdata_i;
            wstrb_q <= s_axi_wstrb_i;
            state_q <= ST_WR_EXEC;
          end else if (s_axi_arvalid_i) begin
            addr_q  <= s_axi_araddr_i;
            state_q <= ST_RD_EXEC;
          end
        end

        ST_WR_EXEC: begin
          // Yazma 1 clock'ta gerçekleşir, sonra yanıt ver
          state_q <= ST_WR_RESP;
        end

        ST_WR_RESP: begin
          if (s_axi_bready_i)
            state_q <= ST_IDLE;
        end

        ST_RD_EXEC: begin
          // Okuma combinational — 1 cycle sonra yakala
          rdata_q <= mem_rdata;
          state_q <= ST_RD_RESP;
        end

        ST_RD_RESP: begin
          if (s_axi_rready_i)
            state_q <= ST_IDLE;
        end

        default: state_q <= ST_IDLE;
      endcase
    end
  end

  // ════════════════════════════════════════════════
  // AXI handshake çıkışları
  // ════════════════════════════════════════════════
  assign s_axi_awready_o = (state_q == ST_IDLE);
  assign s_axi_wready_o  = (state_q == ST_IDLE);
  assign s_axi_arready_o = (state_q == ST_IDLE) && !s_axi_awvalid_i; // yazma öncelikli

  assign s_axi_bresp_o   = AXI_RESP_OKAY;
  assign s_axi_bvalid_o  = (state_q == ST_WR_RESP);

  assign s_axi_rdata_o   = rdata_q;
  assign s_axi_rresp_o   = AXI_RESP_OKAY;
  assign s_axi_rvalid_o  = (state_q == ST_RD_RESP);

  // ════════════════════════════════════════════════
  // DMEM bağlantı sinyalleri
  // ════════════════════════════════════════════════
  assign mem_write    = (state_q == ST_WR_EXEC);
  assign mem_read     = (state_q == ST_RD_EXEC);
  assign mem_addr     = addr_q;
  assign mem_wdata    = wdata_q;
  assign mem_size     = mem_write ? wstrb_to_size(wstrb_q) : 2'b10;  // read: word
  assign mem_unsigned = 1'b1;   // AXI tarafında sign-extend yapılmaz; ham veri döner

  // ════════════════════════════════════════════════
  // DMEM instance
  // ════════════════════════════════════════════════
  dmem #(
    .DMemInitFile (DMEM_INIT_FILE),
    .BASE         (DMEM_BASE),
    .BYTES        (DMEM_BYTES)
  ) u_dmem (
    .clk_i         (clk_i),
    .rstn_i        (rstn_i),
    .mem_read_i    (mem_read),
    .mem_write_i   (mem_write),
    .mem_size_i    (mem_size),
    .mem_unsigned_i(mem_unsigned),
    .addr_i        (mem_addr),
    .wdata_i       (mem_wdata),
    .dbg_addr_i    (dbg_addr_i),
    .rdata_o       (mem_rdata),
    .dbg_data_o    (dbg_data_o)
  );

endmodule
