`timescale 1ns / 1ps

module branch_compare 
import riscv_pkg::*;
#(
)(
       input logic [XLEN-1:0] rs1_i,
       input logic [XLEN-1:0] rs2_i,
       input logic [2:0]      funct3_i,
       
       output logic           take_o
    );
//        logic eq  = (rs1_i == rs2_i);
//        logic lt  = ($signed(rs1_i) < $signed(rs2_i)); //less than
//        logic ltu = (rs1_i < rs2_i);                   //less than unsigned 
        always_comb begin
            unique case (funct3_i)
                3'b000 : take_o = (rs1_i == rs2_i);       //branch equal (beq)
                3'b001 : take_o = (rs1_i != rs2_i);      //branch not equal(bne)
                3'b100 : take_o = ($signed(rs1_i) < $signed(rs2_i));       //less than (blt)
                3'b101 : take_o = ($signed(rs1_i) >= $signed(rs2_i));        //greater equal (bge)
                3'b110 : take_o = (rs1_i < rs2_i);      //branch less than unsigned (bltu)
                3'b111 : take_o = (rs1_i >= rs2_i);     //branch greater equal unsigned (bgeu)
                default: take_o = 1'b0;
            endcase
        end 
endmodule
