`timescale 1ns / 1ps

module alu 
import riscv_pkg::*;
#(
)(
       input logic [XLEN-1:0]   a_i,
       input logic [XLEN-1:0]   b_i,
       input logic [3:0]        alu_ctrl_i,
       
       output logic [XLEN-1:0]  y_o,
       output logic             zero_o,
       output logic             lt_signed_o,
       output logic             lt_unsigned_o        
);
       localparam ADD  = 4'b0000;   // a + b
       localparam SUB  = 4'b0001;   // a - b
       localparam SLL  = 4'b0010;   // a << b[4:0]
       localparam SLT  = 4'b0011;   // a < b
       localparam SLTU = 4'b0100;   // a < b (unsigned)
       localparam XOR_ = 4'b0101;   // a ^ b
       localparam SRL  = 4'b0110;   // a >> b[4:0]
       localparam SRA  = 4'b0111;   // a >>> b[4:0]
       localparam OR_  = 4'b1000;   // a | b
       localparam AND_ = 4'b1001;   // a & b
       
       wire [4:0] shamt = b_i[4:0]; //shift a
       
       always_comb begin
            unique case(alu_ctrl_i)
                ADD  : y_o = a_i + b_i;
                SUB  : y_o = a_i - b_i;
                SLL  : y_o = a_i << shamt;
                SLT  : y_o = ($signed(a_i) < $signed(b_i)) ? 32'd1 : 32'd0;
                SLTU : y_o = (a_i < b_i) ? 32'd1 : 32'd0;
                XOR_ : y_o = a_i ^ b_i;
                SRL  : y_o = a_i >> shamt; 
                SRA  : y_o = $signed(a_i) >>> shamt;
                OR_  : y_o = a_i | b_i;
                AND_ : y_o = a_i & b_i;
                default: y_o = '0;
            endcase   
       end
       
       assign zero_o        = (y_o == '0);
       assign lt_signed_o   = ($signed(a_i) < $signed(b_i));
       assign lt_unsigned_o = (a_i < b_i);
       
endmodule
