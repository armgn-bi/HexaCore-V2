`timescale 1ns / 1ps

module imem
import riscv_pkg::*;
#(
    parameter string IMemInitFile = "C:/Users/DELL/Downloads/HexaCore-V2/PROJE/imem.mem",
    parameter logic [XLEN-1:0] BASE = 32'h8000_0000,
    parameter int WORDS = 16384,
    parameter int ADDR_WIDTH = 14  // Log2(WORDS) - optimized for RAM/DRAM mapping
)(
    input logic  [XLEN-1:0] addr_i,

    output logic [XLEN-1:0] instr_o
 );

    // Block RAM for instruction memory (ROM) - Vivado BRAM inference
    (* rom_style = "block" *) logic [XLEN-1:0] mem [0:WORDS-1];

    // Initialize memory (for simulation only)
    // Vivado synthesis ignores this
    initial if(IMemInitFile != "") $readmemh(IMemInitFile, mem);

    // Address calculation - parameterized for flexible RAM/DRAM mapping
    logic [XLEN-1:0] addr_off;
    assign addr_off = addr_i - BASE;
    localparam int WORDS_BITS = $clog2(WORDS);
    wire [WORDS_BITS-1:0] index = addr_off [2 +: WORDS_BITS];

    // Read from memory (asynchronous read for ROM)
    assign instr_o = mem[index];

endmodule
