`timescale 1ns / 1ps

module alu_control
import riscv_pkg::*;
#(
)(
      input logic [6:0] opcode_i,
      input logic [2:0] funct3_i,
      input logic       funct7b5_i, // instr[30]
      
      output logic [3:0] alu_ctrl_o

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
        
       localparam [6:0] OP    = 7'b0110011;    //OPERATION (51)
       localparam [6:0] OPIMM = 7'b0010011; //OPERATION IMMEDIATE (19)
          
        always_comb begin
            unique case(opcode_i)
                OP: begin
                    unique case(funct3_i)
                        3'b000: alu_ctrl_o   = (funct7b5_i ? SUB : ADD);
                        3'b001: alu_ctrl_o   = SLL;
                        3'b010: alu_ctrl_o   = SLT;
                        3'b011: alu_ctrl_o   = SLTU;
                        3'b100: alu_ctrl_o   = XOR_;
                        3'b101: alu_ctrl_o   = (funct7b5_i ? SRA : SRL);
                        3'b110: alu_ctrl_o   = OR_;
                        3'b111: alu_ctrl_o   = AND_;
                        default : alu_ctrl_o = ADD;
                    endcase
                end
                
                OPIMM: begin
                    unique case(funct3_i)
                        3'b000: alu_ctrl_o   = ADD;                       // addi  [(funct7b5_i ? SUB : ADD);] --> + reg - imm
                        3'b001: alu_ctrl_o   = SLL;                       // slli 
                        3'b010: alu_ctrl_o   = SLT;                       // slti                
                        3'b011: alu_ctrl_o   = SLTU;                      // sltui                 
                        3'b100: alu_ctrl_o   = XOR_;                      // xori                 
                        3'b101: alu_ctrl_o   = (funct7b5_i ? SRA : SRL);  // srli or srai (up to value of funct7b5_i)
                        3'b110: alu_ctrl_o   = OR_;                       // or
                        3'b111: alu_ctrl_o   = AND_;                      // and
                        default : alu_ctrl_o = ADD;                    
                    endcase    
                end
              default: alu_ctrl_o = ADD;
            endcase
        end   
endmodule