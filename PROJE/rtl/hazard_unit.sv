`timescale 1ns / 1ps

module hazard_unit(
        input logic       mem_readE,   //ID/EX'teki komut load mý?
        input logic [4:0] rdE,          //ID/EX'teki target
        input logic [4:0] rs1D,         //IF/ID'deki kaynak 1
        input logic [4:0] rs2D,         //IF/ID'deki kaynak 2
                     
        output logic      stallF,       //PC yazýmý dursun
        output logic      stallD,       // IF/ID yazýmý dursun
        output logic      flushE        // ID/EXkontrol bitlerini 0'la (bubble)   
    );
  
        wire load_use = mem_readE && (rdE != 5'd0) && ((rdE == rs1D) || (rdE == rs2D));
        
        assign  stallF = load_use;
        assign  stallD = load_use;
        assign  flushE = load_use;

endmodule
