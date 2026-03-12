`timescale 1ns / 1ps

module dmem 
import riscv_pkg::*;
#(
    parameter string DMemInitFile = "dmem.mem",
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

    logic [7:0] mem [0:BYTES-1];
    initial if (DMemInitFile != "") $readmemh (DMemInitFile,mem);
      
    //WRITE
    logic [XLEN-1:0] dmem_off;
    assign dmem_off = addr_i - BASE;
    localparam int BYTE_BITS = $clog2(BYTES);
    wire [BYTE_BITS-1:0] byte_idx_w = dmem_off[0 +: BYTE_BITS];
    
    always_ff @(posedge clk_i) begin
        if(mem_write_i) begin
                unique case(mem_size_i)
                    2'b00: begin
                                mem[byte_idx_w] <= wdata_i [7:0];
                           end
                    2'b01: begin
                                mem[byte_idx_w] <= wdata_i[7:0];
                                mem[byte_idx_w+1] <= wdata_i[15:8];
                           end
                    default: begin
                                mem[byte_idx_w]   <= wdata_i[7:0];   
                                mem[byte_idx_w+1] <= wdata_i[15:8];
                                mem[byte_idx_w+2] <= wdata_i[23:16];   
                                mem[byte_idx_w+3] <= wdata_i[31:24];
                            end
                endcase
        end
    end
    
    //READ
    logic [31:0] temp;  // read temp variable (module scope for Vivado compat)
    always_comb begin
        rdata_o = '0;
        temp = '0;
        if(mem_read_i) begin
                unique case(mem_size_i)
                    2'b00: begin //BYTE READ
                            temp = {24'b0, mem[byte_idx_w]};
                            rdata_o = mem_unsigned_i ? temp : {{24{temp[7]}}, temp[7:0]};
                            end
                    2'b01: begin //HALF READ
                                temp = {16'b0, mem[byte_idx_w + 1], mem[byte_idx_w]};
                                rdata_o = mem_unsigned_i ? temp : {{16{temp[15]}}, temp[15:0]};
                            end
                                default: begin
                                rdata_o = {mem[byte_idx_w+3], mem[byte_idx_w+2],mem[byte_idx_w+1],mem[byte_idx_w]};
                            end
                  endcase
        end
    end
    

    logic [XLEN-1:0] dbg_off;
    assign dbg_off = dbg_addr_i - BASE;
    wire [BYTE_BITS-1:0] dbg_b = dbg_off [0 +: BYTE_BITS];

    assign dbg_data_o = {mem[dbg_b+3], mem[dbg_b+2], mem[dbg_b+1], mem[dbg_b]};  
       
endmodule

