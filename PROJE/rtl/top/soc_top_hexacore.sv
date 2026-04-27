// filepath: rtl/top/soc_top_hexacore.sv
// SoC Üst Modül - HexaChipsers-Core Entegrasyonu
// HexaChipsers-Core (AHB-Lite) → AHB→AXI Bridge → AXI4-Lite Interconnect → Slave'ler
`timescale 1ns / 1ps

module soc_top_hexacore
  import axi_pkg::*;
#(
  parameter string IMEM_INIT_FILE = "imem.mem",
  parameter string DMEM_INIT_FILE = "dmem.mem"
)(
  input  logic             clk_i,
  input  logic             rstn_i,

  // ── Debug / Scoreboard portları ─────────────────
  input  logic [31:0]      dbg_addr_i,
  output logic [31:0]      dbg_data_o,

  // ── Periferal dış bağlantı portları ─────────────────
  // UART
  output logic              uart_tx_o,
  input  logic              uart_rx_i,
  output logic              uart_irq_o,

  // SPI
  output logic              spi_sck_o,
  output logic              spi_mosi_o,
  input  logic              spi_miso_i,
  output logic [3:0]        spi_ss_o,

  // I2C
  inout  wire               i2c_sda_io,
  inout  wire               i2c_scl_io,

  // GPIO
  inout  wire [31:0]        gpio0_io,
  inout  wire [31:0]        gpio1_io,
  inout  wire [31:0]        gpio2_io,

  // INT_GEN
  output logic              int_gen_irq_ext_o,
  output logic [63:0]       int_gen_irq_o,

  // ── Interrupts ───────────────────────────────────────
  input  logic              irq_ext_i,
  input  logic              irq_msoft_i,
  input  logic              irq_mtime_i,
  input  logic [63:0]       irq_i,

  // ── Timer ───────────────────────────────────────────────
  input  logic [31:0]       mtime_i,
  input  logic [31:0]       mtimeh_i
);

  // ══════════════════════════════════════════════
  // HexaChipsers-Core AHB-Lite Master Signals
  // ══════════════════════════════════════════
  wire        cpu_hsel;
  wire [1:0]  cpu_htrans;
  wire        cpu_hwrite;
  wire        cpu_hmastlock;
  wire [ 2:0]  cpu_hsize;
  wire [ 2:0]  cpu_hburst;
  wire [ 3:0]  cpu_hprot;
  wire [31:0] cpu_haddr;
  wire [31:0] cpu_hwdata;
  wire        cpu_hready;
  wire        cpu_hreadyout;
  wire [31:0] cpu_hrdata;
  wire        cpu_hresp;

  // ══════════════════════════════════════════════
  // AHB→AXI Bridge Signals
  // ══════════════════════════════════════════════
  wire [31:0] axi_awaddr;
  wire [2:0]  axi_awprot;
  wire        axi_awvalid;
  wire        axi_awready;

  wire [31:0] axi_wdata;
  wire [3:0]  axi_wstrb;
  wire        axi_wvalid;
  wire        axi_wready;

  wire [1:0]  axi_bresp;
  wire        axi_bvalid;
  wire        axi_bready;

  wire [31:0] axi_araddr;
  wire [2:0]  axi_arprot;
  wire        axi_arvalid;
  wire        axi_arready;

  wire [31:0] axi_rdata;
  wire [1:0]  axi_rresp;
  wire        axi_rvalid;
  wire        axi_rready;

  // ══════════════════════════════════════════════
  // AXI Interconnect Signals
  // ══════════════════════════════════════════════
  wire [31:0] slv_awaddr  [NUM_SLAVES];
  wire [2:0]  slv_awprot  [NUM_SLAVES];
  wire        slv_awvalid [NUM_SLAVES];
  wire        slv_awready [NUM_SLAVES];

  wire [31:0] slv_wdata   [NUM_SLAVES];
  wire [3:0] slv_wstrb   [NUM_SLAVES];
  wire        slv_wvalid  [NUM_SLAVES];
  wire        slv_wready  [NUM_SLAVES];

  wire [1:0]  slv_bresp   [NUM_SLAVES];
  wire        slv_bvalid  [NUM_SLAVES];
  wire        slv_bready  [NUM_SLAVES];

  wire [31:0] slv_araddr  [NUM_SLAVES];
  wire [2:0] slv_arprot  [NUM_SLAVES];
  wire        slv_arvalid [NUM_SLAVES];
  wire        slv_arready [NUM_SLAVES];

  wire [31:0] slv_rdata   [NUM_SLAVES];
  wire [1:0]  slv_rresp   [NUM_SLAVES];
  wire        slv_rvalid  [NUM_SLAVES];
  wire        slv_rready  [NUM_SLAVES];

  // ══════════════════════════════════════════════
  // HexaChipsers-Core Instance
  // ════════════════════════════════════════════
  HexaCore
    #(
        .HART_COUNT (1)
    )
  u_hexacore (
    .RES_ORG                  (~rstn_i),
    .RES_SYS                  (),
    .CLK                     (clk_i),
    .STBY_REQ                 (1'b0),
    .STBY_ACK                 (),
    .TRSTn                    (1'b1),
    .SRSTn_IN                 (rstn_i),
    .SRSTn_OUT                (),
    .FORCE_HALT_ON_RESET_REQ  (1'b0),
    .FORCE_HALT_ON_RESET_ACK  (),
    .JTAG_DR_USER_IN          (32'h0),
    .JTAG_DR_USER_OUT         (),
    .TCK                      (1'b0),
    .TMS                      (1'b0),
    .TDI                      (1'b0),
    .TDO_D                    (),
    .TDO_E                    (),
    .RTCK                     (),
    .RESET_VECTOR            ({32'h8000_0000}),
    .DEBUG_SECURE             (1'b0),
    .DEBUG_SECURE_CODE_0      (32'h0),
    .DEBUG_SECURE_CODE_1      (32'h0),
    .CPUI_M_HSEL              ({cpu_hsel}),
    .CPUI_M_HTRANS            ({cpu_htrans}),
    .CPUI_M_HWRITE            ({cpu_hwrite}),
    .CPUI_M_HMASTLOCK         ({cpu_hmastlock}),
    .CPUI_M_HSIZE             ({cpu_hsize}),
    .CPUI_M_HBURST            ({cpu_hburst}),
    .CPUI_M_HPROT             ({cpu_hprot}),
    .CPUI_M_HADDR             ({cpu_haddr}),
    .CPUI_M_HWDATA            ({cpu_hwdata}),
    .CPUI_M_HREADY            ({cpu_hready}),
    .CPUI_M_HREADYOUT         ({cpu_hreadyout}),
    .CPUI_M_HRDATA            ({cpu_hrdata}),
    .CPUI_M_HRESP             ({cpu_hresp}),
    .CPUD_M_HSEL              ({cpu_hsel}),
    .CPUD_M_HTRANS            ({cpu_htrans}),
    .CPUD_M_HWRITE            ({cpu_hwrite}),
    .CPUD_M_HMASTLOCK         ({cpu_hmastlock}),
    .CPUD_M_HSIZE             ({cpu_hsize}),
    .CPUD_M_HBURST            ({cpu_hburst}),
    .CPUD_M_HPROT             ({cpu_hprot}),
    .CPUD_M_HADDR             ({cpu_haddr}),
    .CPUD_M_HWDATA            ({cpu_hwdata}),
    .CPUD_M_HREADY            ({cpu_hready}),
    .CPUD_M_HREADYOUT         ({cpu_hreadyout}),
    .CPUD_M_HRDATA            ({cpu_hrdata}),
    .CPUD_M_HRESP             ({cpu_hresp}),
    .DBGD_M_HSEL              ({cpu_hsel}),
    .DBGD_M_HTRANS            ({cpu_htrans}),
    .DBGD_M_HWRITE            ({cpu_hwrite}),
    .DBGD_M_HMASTLOCK         ({cpu_hmastlock}),
    .DBGD_M_HSIZE             ({cpu_hsize}),
    .DBGD_M_HBURST            ({cpu_hburst}),
    .DBGD_M_HPROT             ({cpu_hprot}),
    .DBGD_M_HADDR             ({cpu_haddr}),
    .DBGD_M_HWDATA            ({cpu_hwdata}),
    .DBGD_M_HREADY            ({cpu_hready}),
    .DBGD_M_HREADYOUT         ({cpu_hreadyout}),
    .DBGD_M_HRDATA            ({cpu_hrdata}),
    .DBGD_M_HRESP             ({cpu_hresp}),
    .IRQ_EXT                  (irq_ext_i),
    .IRQ_MSOFT                (irq_msoft_i),
    .IRQ_MTIME                (irq_mtime_i),
    .IRQ                      (irq_i),
    .MTIME                   (mtime_i),
    .MTIMEH                  (mtimeh_i)
  );

  // ════════════════════════════════════════════════
  // AHB→AXI Bridge
  // ══════════════════════════════════════════════
  ahb_to_axi_bridge u_ahb_axi_bridge (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    // AHB-Lite Slave Interface
    .ahb_hsel_i       (cpu_hsel),
    .ahb_htrans_i     (cpu_htrans),
    .ahb_hwrite_i     (cpu_hwrite),
    .ahb_hsize_i      (cpu_hsize),
    .ahb_hburst_i     (cpu_hburst),
    .ahb_hprot_i      (cpu_hprot),
    .ahb_haddr_i      (cpu_haddr),
    .ahb_hwdata_i     (cpu_hwdata),
    .ahb_hready_i     (cpu_hready),
    .ahb_hready_o     (cpu_hreadyout),
    .ahb_hrdata_o     (cpu_hrdata),
    .ahb_hresp_o      (cpu_hresp),

    // AXI4-Lite Master Interface
    .m_axi_awaddr_o   (axi_awaddr),
    .m_axi_awprot_o   (axi_awprot),
    .m_axi_awvalid_o  (axi_awvalid),
    .m_axi_awready_i  (axi_awready),
    .m_axi_wdata_o    (axi_wdata),
    .m_axi_wstrb_o    (axi_wstrb),
    .m_axi_wvalid_o   (axi_wvalid),
    .m_axi_wready_i   (axi_wready),
    .m_axi_bresp_i    (axi_bresp),
    .m_axi_bvalid_i   (axi_bvalid),
    .m_axi_bready_o   (axi_bready),
    .m_axi_araddr_o   (axi_araddr),
    .m_axi_arprot_o   (axi_arprot),
    .m_axi_arvalid_o  (axi_arvalid),
    .m_axi_arready_i  (axi_arready),
    .m_axi_rdata_i    (axi_rdata),
    .m_axi_rresp_i    (axi_rresp),
    .m_axi_rvalid_i   (axi_rvalid),
    .m_axi_rready_o   (axi_rready)
  );

  // ════════════════════════════════════════════════
  // AXI Interconnect
  // ══════════════════════════════════════════════
  axi_interconnect u_interconnect (
    .clk_i         (clk_i),
    .rstn_i        (rstn_i),

    // Master
    .m_awaddr_i    (axi_awaddr),
    .m_awprot_i    (axi_awprot),
    .m_awvalid_i   (axi_awvalid),
    .m_awready_o   (axi_awready),
    .m_wdata_i     (axi_wdata),
    .m_wstrb_i     (axi_wstrb),
    .m_wvalid_i    (axi_wvalid),
    .m_wready_o    (axi_wready),
    .m_bresp_o     (axi_bresp),
    .m_bvalid_o    (axi_bvalid),
    .m_bready_i    (axi_bready),
    .m_araddr_i    (axi_araddr),
    .m_arprot_i    (axi_arprot),
    .m_arvalid_i   (axi_arvalid),
    .m_arready_o   (axi_arready),
    .m_rdata_o     (axi_rdata),
    .m_rresp_o     (axi_rresp),
    .m_rvalid_o    (axi_rvalid),
    .m_rready_i    (axi_rready),

    // Slaves
    .s_awaddr_o    (slv_awaddr),
    .s_awprot_o    (slv_awprot),
    .s_awvalid_o   (slv_awvalid),
    .s_awready_i   (slv_awready),
    .s_wdata_o     (slv_wdata),
    .s_wstrb_o     (slv_wstrb),
    .s_wvalid_o    (slv_wvalid),
    .s_wready_i    (slv_wready),
    .s_bresp_i     (slv_bresp),
    .s_bvalid_i    (slv_bvalid),
    .s_bready_o    (s_bready),
    .s_araddr_o    (slv_araddr),
    .s_arprot_o    (slv_arprot),
    .s_arvalid_o   (slv_arvalid),
    .s_arready_i   (slv_arready),
    .s_rdata_i     (slv_rdata),
    .s_rresp_i     (slv_rresp),
    .s_rvalid_i    (slv_rvalid),
    .s_rready_o    (slv_rready)
  );

  // ════════════════════════════════════════════════
  // Slave 0: DMEM (AXI Wrapper)
  // ════════════════════════════════════════════
  axi_dmem_slave #(
    .DMEM_INIT_FILE (DMEM_INIT_FILE),
    .DMEM_BASE      (32'h8001_0000),
    .DMEM_BYTES     (32768)
  ) u_axi_dmem (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    .s_axi_awaddr_i   (slv_awaddr  [SLV_DMEM]),
    .s_axi_awprot_i   (slv_awprot  [SLV_DMEM]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_DMEM]),
    .s_axi_awready_o  (slv_awready [SLV_DMEM]),
    .s_axi_wdata_i    (slv_wdata   [SLV_DMEM]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_DMEM]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_DMEM]),
    .s_axi_wready_o   (slv_wready  [SLV_DMEM]),
    .s_axi_bresp_o    (slv_bresp   [SLV_DMEM]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_DMEM]),
    .s_axi_bready_i   (slv_bready  [SLV_DMEM]),
    .s_axi_araddr_i   (slv_araddr  [SLV_DMEM]),
    .s_axi_arprot_i   (slv_arprot  [SLV_DMEM]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_DMEM]),
    .s_axi_arready_o  (slv_arready [SLV_DMEM]),
    .s_axi_rdata_o    (slv_rdata   [SLV_DMEM]),
    .s_axi_rresp_o    (slv_rresp   [SLV_DMEM]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_DMEM]),
    .s_axi_rready_i   (slv_rready  [SLV_DMEM]),

    .dbg_addr_i       (dbg_addr_i),
    .dbg_data_o       (dbg_data_o)
  );

  // ══════════════════════════════════════════════
  // Slave 1: UART (AXI Wrapper)
  // ══════════════════════════════════════════════
  axi_uart #(
    .UART_BASE (32'h4000_0000)
  ) u_axi_uart (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    .s_axi_awaddr_i   (slv_awaddr  [SLV_UART]),
    .s_axi_awprot_i   (slv_awprot  [SLV_UART]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_UART]),
    .s_axi_awready_o  (slv_awready [SLV_UART]),
    .s_axi_wdata_i    (slv_wdata   [SLV_UART]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_UART]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_UART]),
    .s_axi_wready_o   (slv_wready  [SLV_UART]),
    .s_axi_bresp_o    (slv_bresp   [SLV_UART]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_UART]),
    .s_axi_bready_i   (slv_bready  [SLV_UART]),
    .s_axi_araddr_i   (slv_araddr  [SLV_UART]),
    .s_axi_arprot_i   (slv_arprot  [SLV_UART]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_UART]),
    .s_axi_arready_o  (slv_arready [SLV_UART]),
    .s_axi_rdata_o    (slv_rdata   [SLV_UART]),
    .s_axi_rresp_o    (slv_rresp   [SLV_UART]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_UART]),
    .s_axi_rready_i   (slv_rready  [SLV_UART]),

    .uart_tx_o        (uart_tx_o),
    .uart_rx_i        (uart_rx_i),
    .uart_irq_o       (uart_irq_o)
  );

  // ════════════════════════════════════════════════
  // Slave 2: SPI (AXI Wrapper)
  // ════════════════════════════════════════════════
  axi_spi #(
    .SPI_BASE (32'h4000_0100)
  ) u_axi_spi (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    .s_axi_awaddr_i   (slv_awaddr  [SLV_SPI]),
    .s_axi_awprot_i   (slv_awprot  [SLV_SPI]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_SPI]),
    .s_axi_awready_o  (slv_awready [SLV_SPI]),
    .s_axi_wdata_i    (slv_wdata   [SLV_SPI]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_SPI]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_SPI]),
    .s_axi_wready_o   (slv_wready  [SLV_SPI]),
    .s_axi_bresp_o    (slv_bresp   [SLV_SPI]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_SPI]),
    .s_axi_bready_i   (slv_bready  [SLV_SPI]),
    .s_axi_araddr_i   (slv_araddr  [SLV_SPI]),
    .s_axi_arprot_i   (slv_arprot  [SLV_SPI]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_SPI]),
    .s_axi_arready_o  (slv_arready [SLV_SPI]),
    .s_axi_rdata_o    (slv_rdata   [SLV_SPI]),
    .s_axi_rresp_o    (slv_rresp   [SLV_SPI]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_SPI]),
    .s_axi_rready_i   (slv_rready  [SLV_SPI]),

    .spi_sck_o        (spi_sck_o),
    .spi_mosi_o       (spi_mosi_o),
    .spi_miso_i       (spi_miso_i),
    .spi_ss_o         (spi_ss_o)
  );

  // ══════════════════════════════════════════════════════
  // Slave 3: I2C (AXI Wrapper)
  // ════════════════════════════════════════════════
  axi_i2c #(
    .I2C_BASE (32'h4000_0200)
  ) u_axi_i2c (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    .s_axi_awaddr_i   (slv_awaddr  [SLV_I2C]),
    .s_axi_awprot_i   (slv_awprot  [SLV_I2C]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_I2C]),
    .s_axi_awready_o  (slv_awready [SLV_I2C]),
    .s_axi_wdata_i    (slv_wdata   [SLV_I2C]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_I2C]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_I2C]),
    .s_axi_wready_o   (slv_wready  [SLV_I2C]),
    .s_axi_bresp_o    (slv_bresp   [SLV_I2C]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_I2C]),
    .s_axi_bready_i   (slv_bready  [SLV_I2C]),
    .s_axi_araddr_i   (slv_araddr  [SLV_I2C]),
    .s_axi_arprot_i   (slv_arprot  [SLV_I2C]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_I2C]),
    .s_axi_arready_o  (slv_arready [SLV_I2C]),
    .s_axi_rdata_o    (slv_rdata   [SLV_I2C]),
    .s_axi_rresp_o    (slv_rresp   [SLV_I2C]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_I2C]),

    .i2c_sda_io       (i2c_sda_io),
    .i2c_scl_io       (i2c_scl_io)
  );

  // ══════════════════════════════════════════════════════════
  // Slave 4: DSP FIR Filtre (AXI4-Lite Wrapper)
  // ════════════════════════════════════════════════
  dsp_filter_wrapper u_dsp_filter (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    .s_axi_awaddr_i   (slv_awaddr  [SLV_DSP]),
    .s_axi_awprot_i   (slv_awprot  [SLV_DSP]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_DSP]),
    .s_axi_awready_o  (slv_awready [SLV_DSP]),
    .s_axi_wdata_i    (slv_wdata   [SLV_DSP]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_DSP]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_DSP]),
    .s_axi_wready_o   (slv_wready  [SLV_DSP]),
    .s_axi_bresp_o    (slv_bresp   [SLV_DSP]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_DSP]),
    .s_axi_bready_i   (slv_bready  [SLV_DSP]),
    .s_axi_araddr_i   (slv_araddr  [SLV_DSP]),
    .s_axi_arprot_i   (slv_arprot  [SLV_DSP]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_DSP]),
    .s_axi_arready_o  (slv_arready [SLV_DSP]),
    .s_axi_rdata_o    (slv_rdata   [SLV_DSP]),
    .s_axi_rresp_o    (slv_rresp   [SLV_DSP]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_DSP]),
    .s_axi_rready_i   (slv_rready [SLV_DSP])
  );

  // ══════════════════════════════════════════════════════════
  // Slave 5: DQN Inference Accelerator (AXI4-Lite Wrapper)
  // ════════════════════════════════════════════════════════
  dqn_accelerator u_dqn_accel (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    .s_axi_awaddr_i   (slv_awaddr  [SLV_DQN]),
    .s_axi_awprot_i   (slv_awprot  [SLV_DQN]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_DQN]),
    .s_axi_awready_o  (slv_awready [SLV_DQN]),
    .s_axi_wdata_i    (slv_wdata   [SLV_DQN]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_DQN]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_DQN]),
    .s_axi_wready_o   (slv_wready  [SLV_DQN]),
    .s_axi_bresp_o    (slv_bresp   [SLV_DQN]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_DQN]),
    .s_axi_bready_i   (slv_bready [SLV_DQN]),
    .s_axi_araddr_i   (slv_araddr  [SLV_DQN]),
    .s_axi_arprot_i   (slv_arprot  [SLV_DQN]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_DQN]),
    .s_axi_arready_o  (slv_arready [SLV_DQN]),
    .s_axi_rdata_o    (slv_rdata   [SLV_DQN]),
    .s_axi_rresp_o    (slv_rresp   [SLV_DQN]),
    .s_axi_rvalid_o   (slv_rvalid [SLV_DQN]),
    .s_axi_rready_i   (slv_rready [SLV_DQN])
  );

  // ════════════════════════════════════════════════════════════
  // Slave 6: GPIO (AXI Wrapper)
  // ════════════════════════════════════════════════════════
  axi_gpio #(
    .GPIO_BASE (32'hA000_0000)
  ) u_axi_gpio (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    .s_axi_awaddr_i   (slv_awaddr  [SLV_GPIO]),
    .s_axi_awprot_i   (slv_awprot  [SLV_GPIO]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_GPIO]),
    .s_axi_awready_o  (slv_awready [SLV_GPIO]),
    .s_axi_wdata_i    (slv_wdata   [SLV_GPIO]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_GPIO]),
    .s_axi_wvalid_i   (slv_wvalid [SLV_GPIO]),
    .s_axi_wready_o   (slv_wready  [SLV_GPIO]),
    .s_axi_bresp_o    (slv_bresp   [SLV_GPIO]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_GPIO]),
    .s_axi_bready_i   (slv_bready [SLV_GPIO]),
    .s_axi_araddr_i   (slv_araddr  [SLV_GPIO]),
    .s_axi_arprot_i   (slv_arprot  [SLV_GPIO]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_GPIO]),
    .s_axi_arready_o  (slv_arready [SLV_GPIO]),
    .s_axi_rdata_o    (slv_rdata   [SLV_GPIO]),
    .s_axi_rresp_o    (slv_rresp   [SLV_GPIO]),
    .s_axi_rvalid_o   (slv_rvalid [SLV_GPIO]),
    .s_axi_rready_i   (slv_rready [SLV_GPIO]),

    .gpio0_io         (gpio0_io),
    .gpio1_io         (gpio1_io),
    .gpio2_io         (gpio2_io)
  );

  // ════════════════════════════════════════════════════════════════
  // Slave 7: INT_GEN (AXI Wrapper)
  // ════════════════════════════════════════════════════════
  axi_int_gen #(
    .INTGEN_BASE (32'hC000_0000)
  ) u_axi_int_gen (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    .s_axi_awaddr_i   (slv_awaddr  [SLV_INTGEN]),
    .s_axi_awprot_i   (slv_awprot  [SLV_INTGEN]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_INTGEN]),
    .s_axi_awready_o  (slv_awready [SLV_INTGEN]),
    .s_axi_wdata_i    (slv_wdata   [SLV_INTGEN]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_INTGEN]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_INTGEN]),
    .s_axi_wready_o   (slv_wready  [SLV_INTGEN]),
    .s_axi_bresp_o    (slv_bresp   [SLV_INTGEN]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_INTGEN]),
    .s_axi_bready_i   (slv_bready [SLV_INTGEN]),
    .s_axi_araddr_i   (slv_araddr  [SLV_INTGEN]),
    .s_axi_arprot_i   (slv_arprot  [SLV_INTGEN]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_INTGEN]),
    .s_axi_arready_o  (slv_arready [SLV_INTGEN]),
    .s_axi_rdata_o    (slv_rdata   [SLV_INTGEN]),
    .s_axi_rresp_o    (slv_rresp   [SLV_INTGEN]),
    .s_axi_rvalid_o   (slv_rvalid [SLV_INTGEN]),
    .s_axi_rready_i   (slv_rready [SLV_INTGEN]),

    .irq_ext_o        (int_gen_irq_ext_o),
    .irq_o            (int_gen_irq_o)
  );

endmodule
