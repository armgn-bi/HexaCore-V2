    `timescale 1ns / 1ps

module forwarding_unit(
        input logic       reg_writeM,
        input logic [4:0] rdM,
        input logic       reg_writeW,
        input logic [4:0] rdW,
        input logic [4:0] rs1E,
        input logic [4:0] rs2E,
        
        output logic [1:0] forwardA, //10: EX/MEM, 01: MEM/WB, 00: from ID/EX
        output logic [1:0] forwardB 
    );
    
        always_comb begin      
        //A
            if(reg_writeM && (rdM != 5'd0) && (rdM == rs1E)) 
                forwardA = 2'b10;    //EX/MEM
            else if(reg_writeW && (rdW != 5'd0) && (rdW == rs1E))
                forwardA = 2'b01;    //MEM/WB
            else
                forwardA = 2'b00;
        //b
            if(reg_writeM && (rdM != 5'd0) && (rdM == rs2E))
                forwardB = 2'b10;
            else if (reg_writeW && (rdW != 5'd0) && (rdW == rs2E))
                forwardB = 2'b01;
            else
                forwardB = 2'b00;
            end       
endmodule
