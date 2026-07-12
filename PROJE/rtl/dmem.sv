// filepath: rtl/dmem.sv
// Data Memory for RISC-V Core
`timescale 1ns / 1ps

module dmem
  import riscv_pkg::*;
  #(
    parameter string DMemInitFile = "C:/Users/DELL/Downloads/HexaCore-V2/PROJE/dmem.mem",
    parameter logic [XLEN-1:0] BASE = 32'h8000_0000,
    parameter int BYTES = 32768
  )(
    input logic             clk_i,
    input logic             rstn_i,
    input logic             mem_read_i,
    input logic             mem_write_i,
    input logic [1:0]       mem_size_i,
    input logic             mem_unsigned_i,
    input logic [XLEN-1:0]  addr_i,
    input logic [XLEN-1:0]  wdata_i,
    input logic [XLEN-1:0]  dbg_addr_i,

    output logic [XLEN-1:0] rdata_o,
    output logic [XLEN-1:0] dbg_data_o
  );

  // Memory declaration with block RAM attribute for inference and initialization
  (* ram_style = "block", ram_init_file = "C:/Users/DELL/Downloads/HexaCore-V2/PROJE/dmem.mem" *)
  logic [31:0] mem [0:BYTES/4-1];  // Word-based memory for BRAM inference

  // WRITE
  logic [XLEN-1:0] dmem_off;
  assign dmem_off = addr_i - BASE;
  localparam int BYTE_BITS = $clog2(BYTES);
  localparam int WORD_BITS = $clog2(BYTES/4);
  wire [BYTE_BITS-1:0] byte_idx_w = dmem_off[0 +: BYTE_BITS];
  wire [WORD_BITS-1:0] word_idx_w = dmem_off[2 +: WORD_BITS];  // Word-aligned index

  // Byte enables for word writes
  logic [3:0] byte_en;
  always_comb begin
    byte_en = 4'b0000;
    if (mem_write_i) begin
      case (mem_size_i)
        2'b00: byte_en = 4'b0001 << byte_idx_w[1:0];  // Byte write
        2'b01: byte_en = 4'b0011 << byte_idx_w[1:0];  // Half-word write
        default: byte_en = 4'b1111;  // Word write
      endcase
    end
  end

  // Pipeline puts SB data in wdata_i[7:0], SH in wdata_i[15:0].
  // Replicate across all byte lanes so byte_en selects the right position.
  logic [31:0] wdata_replicated;
  always_comb begin
    case (mem_size_i)
      2'b00:   wdata_replicated = {4{wdata_i[7:0]}};   // Byte: replicate across all lanes
      2'b01:   wdata_replicated = {2{wdata_i[15:0]}};   // Half: replicate across both halves
      default: wdata_replicated = wdata_i;               // Word: pass through
    endcase
  end

  // Registered read path: capture address (word index), size, unsigned for read, and register RAM output
  logic [WORD_BITS-1:0] addr_r;   // registered word address for read
  logic [1:0]      size_r;
  logic            unsigned_r;
  logic [31:0]     mem_read_data_r;   // registered output data from RAM

  always_ff @(posedge clk_i) begin
    // Write operation
    if (mem_write_i) begin
      if (byte_en[0]) mem[word_idx_w][7:0]   <= wdata_replicated[7:0];
      if (byte_en[1]) mem[word_idx_w][15:8]  <= wdata_replicated[15:8];
      if (byte_en[2]) mem[word_idx_w][23:16] <= wdata_replicated[23:16];
      if (byte_en[3]) mem[word_idx_w][31:24] <= wdata_replicated[31:24];
    end
    // Read operation
    if (mem_read_i) begin
      mem_read_data_r <= mem[word_idx_w];
    end
  end

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      addr_r        <= '0;
      size_r        <= '0;
      unsigned_r    <= '0;
    end else begin
      if (mem_read_i) begin
        addr_r    <= word_idx_w;
        size_r    <= mem_size_i;
        unsigned_r<= mem_unsigned_i;
      end
    end
  end

  // Combinatorial output formatting based on registered attributes
  always_comb begin
    // Default output
    rdata_o = '0;
    // Only drive output when we have valid registered data from a read
    if (|size_r) begin  // size_r is non-zero when a read has been captured
      logic [1:0] byte_idx = addr_r[1:0];   // byte index within the word
      logic [XLEN-1:0] temp;
      case (size_r)
        2'b00: begin // BYTE READ
          case (byte_idx)
            2'b00: temp = {24'b0, mem_read_data_r[7:0]};
            2'b01: temp = {24'b0, mem_read_data_r[15:8]};
            2'b10: temp = {24'b0, mem_read_data_r[23:16]};
            2'b11: temp = {24'b0, mem_read_data_r[31:24]};
          endcase
          rdata_o = unsigned_r ? temp : {{24{temp[7]}}, temp[7:0]};
        end
        2'b01: begin // HALF READ
          case (byte_idx)
            2'b00: temp = {16'b0, mem_read_data_r[15:0]};
            2'b10: temp = {16'b0, mem_read_data_r[31:16]};
            default: temp = {16'b0, mem_read_data_r[15:0]};
          endcase
          rdata_o = unsigned_r ? temp : {{16{temp[15]}}, temp[15:0]};
        end
        default: begin // WORD READ
          rdata_o = mem_read_data_r;
        end
      endcase
    end
  end

  // DEBUG PORT (asynchronous read, unchanged)
  logic [XLEN-1:0] dbg_off;
  assign dbg_off = dbg_addr_i - BASE;
  wire [WORD_BITS-1:0] dbg_word_idx = dbg_off[2 +: WORD_BITS];  // Word-aligned index
  assign dbg_data_o = mem[dbg_word_idx];

endmodule