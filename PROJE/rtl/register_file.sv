`timescale 1ns / 1ps

module register_file
import riscv_pkg::*;
#(
)(
       input logic                clk_i,
       input logic                rstn_i,
       input logic                we_i,     //write enable
       input logic [4:0]          rs1_i,    //register source 1
       input logic [4:0]          rs2_i,    //register source 2
       input logic [4:0]          rd_i,     //read data
       input logic [XLEN-1:0]     wd_i,     //write data
       
       output logic [XLEN-1:0]    rd1_o,    //read data 1 
       output logic [XLEN-1:0]    rd2_o     //read data 2 
   );
    
    logic [XLEN-1:0] regs [31:0];   //32-bit 32 register
    
    //Read x0 always 0
    assign rd1_o = (rs1_i == 5'd0) ? '0 : regs[rs1_i];
    assign rd2_o = (rs2_i == 5'd0) ? '0 : regs[rs2_i];
        integer i;  
    //Don't Write to x0
    always_ff @(posedge clk_i) begin
        if(!rstn_i) begin
            for (i=0; i < 32; i = i + 1)
                regs[i] <= '0;
        end else if(we_i && (rd_i != 5'd0)) begin
                regs[rd_i] <= wd_i;
                regs[0] <= '0;
        end    
    end     
endmodule

