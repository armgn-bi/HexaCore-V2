`timescale 1ns / 1ps

module imem 
import riscv_pkg::*;
#(
    parameter string IMemInitFile = "imem.mem",
    parameter logic [XLEN-1:0] BASE = 32'h8000_0000,
    parameter int WORDS = 16384
)(
    input logic  [XLEN-1:0] addr_i,
    
    output logic [XLEN-1:0] instr_o
 );
     logic [XLEN-1:0] mem [0:WORDS-1];
     
     
     initial if(IMemInitFile != "") $readmemh(IMemInitFile, mem);   
     logic [XLEN-1:0] addr_off;  
     assign addr_off = addr_i - BASE;   
     localparam int WORDS_BITS = $clog2(WORDS);
     wire [WORDS_BITS-1:0] index = addr_off [2 +: WORDS_BITS];
     assign instr_o = mem[index];
 
 endmodule 

