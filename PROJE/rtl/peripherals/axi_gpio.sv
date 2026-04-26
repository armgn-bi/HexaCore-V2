// filepath: rtl/peripherals/axi_gpio.sv
// AXI4-Lite Wrapper for PORT (GPIO)
// HexaChipsers-Core PORT modülünü AXI4-Lite bus'una bağlar
`timescale 1ns / 1ps

module axi_gpio
  import axi_pkg::*;
#(
  parameter logic [AXI_ADDR_WIDTH-1:0] GPIO_BASE = 32'hA000_0000
)(
  input  logic                        clk_i,
  input  logic                        rstn_i,

  // AXI4-Lite Slave Interface
  input  logic [AXI_ADDR_WIDTH-1:0]   s_axi_awaddr_i,
  input  logic [2:0]                  s_axi_awprot_i,
  input  logic                        s_axi_awvalid_i,
  output logic                        s_axi_awready_o,

  input  logic [AXI_DATA_WIDTH-1:0]   s_axi_wdata_i,
  input  logic [AXI_STRB_WIDTH-1:0]   s_axi_wstrb_i,
  input  logic                        s_axi_wvalid_i,
  output logic                        s_axi_wready_o,

  output logic [1:0]                  s_axi_bresp_o,
  output logic                        s_axi_bvalid_o,
  input  logic                        s_axi_bready_i,

  input  logic [AXI_ADDR_WIDTH-1:0]   s_axi_araddr_i,
  input  logic [2:0]                  s_axi_arprot_i,
  input  logic                        s_axi_arvalid_i,
  output logic                        s_axi_arready_o,

  output logic [AXI_DATA_WIDTH-1:0]   s_axi_rdata_o,
  output logic [1:0]                  s_axi_rresp_o,
  output logic                        s_axi_rvalid_o,
  input  logic                        s_axi_rready_i,

  // GPIO Ports
  inout  wire [31:0]                  gpio0_io,
  inout  wire [31:0]                  gpio1_io,
  inout  wire [31:0]                  gpio2_io
);

  // ════════════════════════════════════════════════
  // AXI4-Lite to AHB-Lite Bridge Signals
  // ════════════════════════════════════════════════
  logic        ahb_hsel;
  logic [1:0]  ahb_htrans;
  logic        ahb_hwrite;
  logic        ahb_hmastlock;
  logic [2:0]  ahb_hsize;
  logic [2:0]  ahb_hburst;
  logic [3:0]  ahb_hprot;
  logic [31:0] ahb_haddr;
  logic [31:0] ahb_hwdata;
  logic        ahb_hready;
  logic        ahb_hreadyout;
  logic [31:0] ahb_hrdata;
  logic        ahb_hresp;

  // ════════════════════════════════════════════════
  // AXI4-Lite to AHB-Lite Bridge
  // ════════════════════════════════════════════════
  axi_to_ahb_lite_bridge u_axi_ahb_bridge (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    // AXI4-Lite Slave Interface
    .s_axi_awaddr_i   (s_axi_awaddr_i),
    .s_axi_awprot_i   (s_axi_awprot_i),
    .s_axi_awvalid_i  (s_axi_awvalid_i),
    .s_axi_awready_o  (s_axi_awready_o),
    .s_axi_wdata_i    (s_axi_wdata_i),
    .s_axi_wstrb_i    (s_axi_wstrb_i),
    .s_axi_wvalid_i   (s_axi_wvalid_i),
    .s_axi_wready_o   (s_axi_wready_o),
    .s_axi_bresp_i    (s_axi_bresp_o),
    .s_axi_bvalid_i   (s_axi_bvalid_o),
    .s_axi_bready_i   (s_axi_bready_i),
    .s_axi_araddr_i   (s_axi_araddr_i),
    .s_axi_arprot_i   (s_axi_arprot_i),
    .s_axi_arvalid_i  (s_axi_arvalid_i),
    .s_axi_arready_o  (s_axi_arready_o),
    .s_axi_rdata_o    (s_axi_rdata_o),
    .s_axi_rresp_o    (s_axi_rresp_o),
    .s_axi_rvalid_o   (s_axi_rvalid_o),
    .s_axi_rready_i   (s_axi_rready_i),

    // AHB-Lite Master Interface
    .ahb_hsel_o       (ahb_hsel),
    .ahb_htrans_o     (ahb_htrans),
    .ahb_hwrite_o     (ahb_hwrite),
    .ahb_hmastlock_o  (ahb_hmastlock),
    .ahb_hsize_o      (ahb_hsize),
    .ahb_hburst_o     (ahb_hburst),
    .ahb_hprot_o      (ahb_hprot),
    .ahb_haddr_o      (ahb_haddr),
    .ahb_hwdata_o     (ahb_hwdata),
    .ahb_hready_o     (ahb_hready),
    .ahb_hready_i     (ahb_hreadyout),
    .ahb_hrdata_i     (ahb_hrdata),
    .ahb_hresp_i      (ahb_hresp)
  );

  // ════════════════════════════════════════════════
  // PORT Instance
  // ════════════════════════════════════════════════
  PORT u_port (
    .CLK              (clk_i),
    .RES              (~rstn_i),

    // AHB Lite Slave port
    .S_HSEL           (ahb_hsel),
    .S_HTRANS         (ahb_htrans),
    .S_HWRITE         (ahb_hwrite),
    .S_HMASTLOCK      (ahb_hmastlock),
    .S_HSIZE          (ahb_hsize),
    .S_HBURST         (ahb_hburst),
    .S_HPROT          (ahb_hprot),
    .S_HADDR          (ahb_haddr),
    .S_HWDATA         (ahb_hwdata),
    .S_HREADY         (ahb_hready),
    .S_HREADYOUT      (ahb_hreadyout),
    .S_HRDATA         (ahb_hrdata),
    .S_HRESP          (ahb_hresp),

    // GPIO
    .GPIO0            (gpio0_io),
    .GPIO1            (gpio1_io),
    .GPIO2            (gpio2_io)
  );

endmodule
