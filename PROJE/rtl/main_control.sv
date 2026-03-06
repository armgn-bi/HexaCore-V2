`timescale 1ns / 1ps

module main_control(
      input logic  [6:0] opcode_i,
      input logic  [2:0] funct3_i,
      output logic       reg_write_o,
      output logic [2:0] imm_src_o,
      output logic       alu_src_a_pc_o,  // 1=program counter, 0 = rs1
      output logic       alu_src_b_imm_o, // 1=imm , 0 = rs2
      output logic [1:0] result_src_o,    // 00=ALU , 01 = Load , 10 = Program counter + 4
      output logic       mem_read_o,
      output logic       mem_write_o,
      output logic [1:0] mem_size_o,     //00 = Byte, 01 = Half , 11 = Word
      output logic       mem_unsigned_o,
      output logic       branch_o,
      output logic       jal_o,
      output logic       jalr_o,
      output logic       lui_o
   );
    
        localparam [6:0] OP     = 7'b0110011;     // (51)
        localparam [6:0] OPIMM  = 7'b0010011;     // (19)
        localparam [6:0] LOAD   = 7'b0000011;     // (3)
        localparam [6:0] STORE  = 7'b0100011;     // (35)
        localparam [6:0] BRANCH = 7'b1100011;     // (99)
        localparam [6:0] LUI    = 7'b0110111;     //load upper immediate (55)
        localparam [6:0] AUIPC  = 7'b0010111;     //add upper immediate to PC (23)
        localparam [6:0] JAL    = 7'b1101111;     //jump and link (111)
        localparam [6:0] JALR   = 7'b1100111;     //jump and link register (103)
        
        always_comb begin
            reg_write_o     = 1'b0;;
            imm_src_o       = 3'b000;
            alu_src_a_pc_o  = 1'b0;
            alu_src_b_imm_o = 1'b0;
            result_src_o    = 2'b00;
            mem_read_o      = 1'b0;;
            mem_write_o     = 1'b0;  
            mem_size_o      = 2'b10;    
            mem_unsigned_o  = 1'b0;
            branch_o        = 1'b0; 
            jal_o           = 1'b0;        
            jalr_o          = 1'b0;       
            lui_o           = 1'b0;     
            
            unique case(opcode_i)
                OP:
                    reg_write_o = 1;
                OPIMM: begin
                            reg_write_o = 1'b1;
                            alu_src_b_imm_o = 1'b1;
                            imm_src_o = 3'b000;
                       end
                LOAD: begin
                            reg_write_o = 1'b1;
                            alu_src_b_imm_o = 1'b1;
                            imm_src_o = 3'b000;
                            mem_read_o = 1'b1;
                            result_src_o = 2'b01;                   
                unique case(funct3_i)
                    3'b000: begin 
                        mem_size_o = 2'b00; 
                        mem_unsigned_o = 1'b0;
                    end        
                    3'b001: begin             
                        mem_size_o = 2'b01;   
                        mem_unsigned_o = 1'b0;
                    end              
                    3'b010: begin 
                        mem_size_o = 2'b10; 
                        mem_unsigned_o = 1'b0;
                    end        
                    3'b100: begin             
                        mem_size_o = 2'b00;   
                        mem_unsigned_o = 1'b1;
                    end 
                    3'b101: begin 
                        mem_size_o = 2'b01; 
                        mem_unsigned_o = 1'b1;
                    end        
                endcase            
                end
        
               STORE: begin
                       alu_src_b_imm_o = 1'b1;
                       imm_src_o = 3'b001;
                       mem_write_o = 1'b1;
                       unique case(funct3_i)
                            3'b000: mem_size_o = 2'b00; //store byte
                            3'b001: mem_size_o = 2'b01; //store half
                            3'b010: mem_size_o = 2'b10; //store word
                        endcase
                      end
               BRANCH: begin
                        imm_src_o = 3'b010;
                        branch_o  = 1'b1;
                       end
               LUI: begin
                        reg_write_o     = 1'b1;
                        alu_src_b_imm_o = 1'b1;
                        imm_src_o       = 3'b011;
                        lui_o           = 1'b1;
                     end  
               AUIPC: begin
                        reg_write_o     = 1'b1;
                        alu_src_a_pc_o  = 1'b1;
                        alu_src_b_imm_o = 1'b1;
                        imm_src_o       = 3'b011;
                      end
               JAL: begin
                        reg_write_o  = 1'b1;
                        result_src_o = 2'b10; //PC+4
                        imm_src_o    = 3'b100;//J type
                        jal_o        = 1'b1;  
                    end
              JALR: begin
                        reg_write_o     = 1'b1;
                        result_src_o    = 2'b10; 
                        imm_src_o       = 3'b000;
                        jalr_o          = 1'b1;
                        alu_src_b_imm_o = 1'b1;
                    end
              default: begin
                    
              end         
            endcase
        end   
endmodule

