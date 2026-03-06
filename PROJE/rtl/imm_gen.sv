`timescale 1ns / 1ps

module imm_gen 
import riscv_pkg::*;
#(
)(
    input logic [31:0] instr_i,
    input logic [2:0] immsrc_i, //000 = I , 001 = S, 010 = B, 011 = U , 100 = J
    
    output logic [XLEN-1:0] imm_o
    );
    logic [31:0] Iimm;
    logic [31:0] Simm;
    logic [31:0] Bimm;
    logic [31:0] Uimm;
    logic [31:0] Jimm;
    
    
    assign Iimm = {{20{instr_i[31]}}, instr_i [31:20]};
    
    assign Simm = {{20{instr_i[31]}}, instr_i [31:25], instr_i[11:7]};
    
    assign Bimm = {{19{instr_i[31]}}, instr_i [31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
    
    assign Uimm = {instr_i[31:12], 12'b0};
    
    assign Jimm = {{11{instr_i[31]}}, instr_i[31], instr_i [19:12], instr_i[20], instr_i[30:21], 1'b0};
    
    always_comb begin
        unique case(immsrc_i)
           3'b000: imm_o = Iimm;
           3'b001: imm_o = Simm;
           3'b010: imm_o = Bimm;
           3'b011: imm_o = Uimm;
           3'b100: imm_o = Jimm;
           default: imm_o = Iimm;
        endcase
    end   
endmodule

