//===========================================================
// HexaChipsers-Core — AHB Lite RAM Module (BRAM Optimized)
//-----------------------------------------------------------
// Generic byte-addressable RAM with AHB Lite slave interface.
// Optimized for Xilinx BRAM inference.
//===========================================================

`include "defines_chip.v"
`include "defines_core.v"

module RAM
    #(parameter
        RAM_SIZE = 32768 // in bytes
     )
(
    input  wire        CLK,
    input  wire        RES,
    //
    input  wire        S_HSEL,
    input  wire [ 1:0] S_HTRANS,
    input  wire        S_HWRITE,
    input  wire        S_HMASTLOCK,
    input  wire [ 2:0] S_HSIZE,
    input  wire [ 2:0] S_HBURST,
    input  wire [ 3:0] S_HPROT,
    input  wire [31:0] S_HADDR,
    input  wire [31:0] S_HWDATA,
    input  wire        S_HREADY,
    output wire        S_HREADYOUT,
    output wire [31:0] S_HRDATA,
    output wire        S_HRESP
);

//-------------------------------
// Memory Parameters
//-------------------------------
localparam MEM_DEPTH = RAM_SIZE / 4; // word depth
localparam ADDR_W    = $clog2(MEM_DEPTH);

//-------------------------------
// Memory Banks (byte-organized) - BRAM Optimized
//-------------------------------
(* ram_style = "block" *) reg [7:0] mem_0 [0:MEM_DEPTH-1];
(* ram_style = "block" *) reg [7:0] mem_1 [0:MEM_DEPTH-1];
(* ram_style = "block" *) reg [7:0] mem_2 [0:MEM_DEPTH-1];
(* ram_style = "block" *) reg [7:0] mem_3 [0:MEM_DEPTH-1];

//-------------------------------
// Simulation Memory Init
//-------------------------------
`ifdef SIMULATION
initial begin : INIT_MEM
    reg [7:0] rom [0:65535];
    integer a;
    // Clear temp ROM
    for (a = 0; a < 65536; a = a + 1) rom[a] = 8'h00;
    // Load byte-oriented hex file (with @address format)
    $readmemh("rom.memh", rom);
    // Distribute to byte banks (up to 16K words = 64KB)
    for (a = 0; a < 16384 && a < MEM_DEPTH; a = a + 1)
    begin
        mem_0[a] = rom[a * 4 + 0];
        mem_1[a] = rom[a * 4 + 1];
        mem_2[a] = rom[a * 4 + 2];
        mem_3[a] = rom[a * 4 + 3];
    end
end
`endif

//-------------------------------
// AHB Data Phase Register
//-------------------------------
reg        dphase;
reg [ 1:0] dphase_htrans;
reg [31:0] dphase_haddr;
reg        dphase_hwrite;
reg [ 2:0] dphase_hsize;

always @(posedge CLK, posedge RES)
begin
    if (RES)
    begin
        dphase        <= 1'b0;
        dphase_htrans <= 2'b00;
        dphase_haddr  <= 32'h00000000;
        dphase_hwrite <= 1'b0;
        dphase_hsize  <= 3'b000;
    end
    else if (S_HREADY & S_HREADYOUT)
    begin
        dphase        <= S_HTRANS[1];
        dphase_htrans <= S_HTRANS;
        dphase_haddr  <= S_HADDR;
        dphase_hwrite <= S_HWRITE;
        dphase_hsize  <= S_HSIZE;
    end
end

//-------------------------------
// Address Decode
//-------------------------------
wire [ADDR_W-1:0] rd_addr = S_HADDR[ADDR_W+1:2];
wire [ADDR_W-1:0] wr_addr = dphase_haddr[ADDR_W+1:2];

//-------------------------------
// Read Enable
//-------------------------------
wire mem_re = S_HREADY & S_HREADYOUT & S_HTRANS[1] & ~S_HWRITE;

//-------------------------------
// Write Enables (byte-lane)
//-------------------------------
wire mem_we_0 = S_HREADY & S_HREADYOUT & dphase & dphase_hwrite
    & ((dphase_hsize == 3'b000) && (dphase_haddr[1:0] == 2'b00)
    || (dphase_hsize == 3'b001) && (dphase_haddr[1]   == 1'b0 )
    || (dphase_hsize == 3'b010));
wire mem_we_1 = S_HREADY & S_HREADYOUT & dphase & dphase_hwrite
    & ((dphase_hsize == 3'b000) && (dphase_haddr[1:0] == 2'b01)
    || (dphase_hsize == 3'b001) && (dphase_haddr[1]   == 1'b0 )
    || (dphase_hsize == 3'b010));
wire mem_we_2 = S_HREADY & S_HREADYOUT & dphase & dphase_hwrite
    & ((dphase_hsize == 3'b000) && (dphase_haddr[1:0] == 2'b10)
    || (dphase_hsize == 3'b001) && (dphase_haddr[1]   == 1'b1 )
    || (dphase_hsize == 3'b010));
wire mem_we_3 = S_HREADY & S_HREADYOUT & dphase & dphase_hwrite
    & ((dphase_hsize == 3'b000) && (dphase_haddr[1:0] == 2'b11)
    || (dphase_hsize == 3'b001) && (dphase_haddr[1]   == 1'b1 )
    || (dphase_hsize == 3'b010));

//-------------------------------
// Write Data
//-------------------------------
wire [7:0] wdata_0 = S_HWDATA[ 7: 0];
wire [7:0] wdata_1 = S_HWDATA[15: 8];
wire [7:0] wdata_2 = S_HWDATA[23:16];
wire [7:0] wdata_3 = S_HWDATA[31:24];

//-------------------------------
// Memory Read/Write - Synchronous for BRAM
//-------------------------------
reg [7:0] rdata_0, rdata_1, rdata_2, rdata_3;

always @(posedge CLK)
begin
    if (mem_we_0) mem_0[wr_addr] <= wdata_0;
    if (mem_re)   rdata_0        <= mem_0[rd_addr];
end

always @(posedge CLK)
begin
    if (mem_we_1) mem_1[wr_addr] <= wdata_1;
    if (mem_re)   rdata_1        <= mem_1[rd_addr];
end

always @(posedge CLK)
begin
    if (mem_we_2) mem_2[wr_addr] <= wdata_2;
    if (mem_re)   rdata_2        <= mem_2[rd_addr];
end

always @(posedge CLK)
begin
    if (mem_we_3) mem_3[wr_addr] <= wdata_3;
    if (mem_re)   rdata_3        <= mem_3[rd_addr];
end

//-------------------------------
// Read-Write Contention Forward
//-------------------------------
reg  contention_0, contention_1, contention_2, contention_3;
reg  [7:0] cdata_0, cdata_1, cdata_2, cdata_3;

always @(posedge CLK, posedge RES)
begin
    if (RES) contention_0 <= 1'b0;
    else if (S_HREADY & S_HREADYOUT & mem_re & mem_we_0)
        contention_0 <= (rd_addr == wr_addr);
    else if (S_HREADY & S_HREADYOUT)
        contention_0 <= 1'b0;
end

always @(posedge CLK, posedge RES)
begin
    if (RES) contention_1 <= 1'b0;
    else if (S_HREADY & S_HREADYOUT & mem_re & mem_we_1)
        contention_1 <= (rd_addr == wr_addr);
    else if (S_HREADY & S_HREADYOUT)
        contention_1 <= 1'b0;
end

always @(posedge CLK, posedge RES)
begin
    if (RES) contention_2 <= 1'b0;
    else if (S_HREADY & S_HREADYOUT & mem_re & mem_we_2)
        contention_2 <= (rd_addr == wr_addr);
    else if (S_HREADY & S_HREADYOUT)
        contention_2 <= 1'b0;
end

always @(posedge CLK, posedge RES)
begin
    if (RES) contention_3 <= 1'b0;
    else if (S_HREADY & S_HREADYOUT & mem_re & mem_we_3)
        contention_3 <= (rd_addr == wr_addr);
    else if (S_HREADY & S_HREADYOUT)
        contention_3 <= 1'b0;
end

always @(posedge CLK, posedge RES)
begin
    if (RES)         cdata_0 <= 8'h00;
    else if (mem_we_0) cdata_0 <= wdata_0;
end

always @(posedge CLK, posedge RES)
begin
    if (RES)         cdata_1 <= 8'h00;
    else if (mem_we_1) cdata_1 <= wdata_1;
end

always @(posedge CLK, posedge RES)
begin
    if (RES)         cdata_2 <= 8'h00;
    else if (mem_we_2) cdata_2 <= wdata_2;
end

always @(posedge CLK, posedge RES)
begin
    if (RES)         cdata_3 <= 8'h00;
    else if (mem_we_3) cdata_3 <= wdata_3;
end

//-------------------------------
// Read Data Output
//-------------------------------
wire [7:0] rd_0 = contention_0 ? cdata_0 : rdata_0;
wire [7:0] rd_1 = contention_1 ? cdata_1 : rdata_1;
wire [7:0] rd_2 = contention_2 ? cdata_2 : rdata_2;
wire [7:0] rd_3 = contention_3 ? cdata_3 : rdata_3;

assign S_HRDATA = (dphase & S_HREADY & S_HREADYOUT) ?
                  {rd_3, rd_2, rd_1, rd_0} : 32'h00000000;

//-------------------------------
// Wait States
//-------------------------------
`ifdef HAVE_RAM_WAIT
reg [3:0] wait_cycle;
reg [3:0] ready_count;

always @(posedge CLK, posedge RES)
begin
    if (RES)
        wait_cycle <= 4'h0;
    else if (S_HREADY & S_HREADYOUT & S_HTRANS[1])
        wait_cycle <= S_HADDR[3:2] & 4'b0011;
    else if (S_HREADY & S_HREADYOUT)
        wait_cycle <= 4'h0;
end

always @(posedge CLK, posedge RES)
begin
    if (RES)
        ready_count <= 4'h0;
    else if (S_HREADY & S_HREADYOUT & S_HTRANS[1])
        ready_count <= 4'h0;
    else if (dphase & (ready_count == wait_cycle))
        ready_count <= 4'h0;
    else if (dphase)
        ready_count <= ready_count + 4'h1;
end

assign S_HREADYOUT = ~dphase | (dphase & (ready_count == wait_cycle));
`else
assign S_HREADYOUT = 1'b1; // zero wait states
`endif

assign S_HRESP = 1'b0; // OKAY response

//------------------------
// End of Module
//------------------------
endmodule

//===========================================================
// End of File
//===========================================================
