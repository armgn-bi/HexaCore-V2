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

    logic [31:0] mem [0:BYTES/4-1];  // Word-based memory for BRAM inference
    initial if (DMemInitFile != "") $readmemh (DMemInitFile,mem);

    //WRITE
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
        if(mem_write_i) begin
            unique case(mem_size_i)
                2'b00: byte_en = 4'b0001 << byte_idx_w[1:0];  // Byte write
                2'b01: byte_en = 4'b0011 << byte_idx_w[1:0];  // Half-word write
                default: byte_en = 4'b1111;  // Word write
            endcase
        end
    end

    always_ff @(posedge clk_i) begin
        if(mem_write_i) begin
            // Read-modify-write for proper BRAM inference
            if(byte_en[0]) mem[word_idx_w][7:0]   <= wdata_i[7:0];
            if(byte_en[1]) mem[word_idx_w][15:8]  <= wdata_i[15:8];
            if(byte_en[2]) mem[word_idx_w][23:16] <= wdata_i[23:16];
            if(byte_en[3]) mem[word_idx_w][31:24] <= wdata_i[31:24];
        end
    end
    
    //READ
    logic [31:0] temp;  // read temp variable (module scope for Vivado compat)
    logic [31:0] read_word;  // Word read from memory
    wire [WORD_BITS-1:0] word_idx_r = dmem_off[2 +: WORD_BITS];  // Word-aligned index

    always_comb begin
        rdata_o = '0;
        temp = '0;
        read_word = mem[word_idx_r];  // Read entire word

        if(mem_read_i) begin
            unique case(mem_size_i)
                2'b00: begin //BYTE READ
                    case(byte_idx_w[1:0])
                        2'b00: temp = {24'b0, read_word[7:0]};
                        2'b01: temp = {24'b0, read_word[15:8]};
                        2'b10: temp = {24'b0, read_word[23:16]};
                        2'b11: temp = {24'b0, read_word[31:24]};
                    endcase
                    rdata_o = mem_unsigned_i ? temp : {{24{temp[7]}}, temp[7:0]};
                end
                2'b01: begin //HALF READ
                    case(byte_idx_w[1:0])
                        2'b00: temp = {16'b0, read_word[15:0]};
                        2'b10: temp = {16'b0, read_word[31:16]};
                        default: temp = {16'b0, read_word[15:0]};
                    endcase
                    rdata_o = mem_unsigned_i ? temp : {{16{temp[15]}}, temp[15:0]};
                end
                default: begin //WORD READ
                    rdata_o = read_word;
                end
            endcase
        end
    end
    

    logic [XLEN-1:0] dbg_off;
    assign dbg_off = dbg_addr_i - BASE;
    wire [WORD_BITS-1:0] dbg_word_idx = dbg_off[2 +: WORD_BITS];  // Word-aligned index

    assign dbg_data_o = mem[dbg_word_idx];  
       
endmodule

