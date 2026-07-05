// filepath: rtl/spi/axi_spi.sv
// AXI4-Lite SPI Master Controller
// Base: 0x4000_0100
`timescale 1ns / 1ps

module axi_spi #(
  parameter AXI_ADDR_WIDTH = 32,
  parameter AXI_DATA_WIDTH = 32,
  parameter CLK_DIV_WIDTH = 8
)(
  input  logic                   clk_i,
  input  logic                   rstn_i,

  // AXI4-Lite Slave Interface
  input  logic [AXI_ADDR_WIDTH-1:0]  s_axi_awaddr_i,
  input  logic [2:0]                  s_axi_awprot_i,
  input  logic                        s_axi_awvalid_i,
  output logic                        s_axi_awready_o,

  input  logic [AXI_DATA_WIDTH-1:0]  s_axi_wdata_i,
  input  logic [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb_i,
  input  logic                        s_axi_wvalid_i,
  output logic                        s_axi_wready_o,

  output logic [1:0]                  s_axi_bresp_o,
  output logic                        s_axi_bvalid_o,
  input  logic                        s_axi_bready_i,

  input  logic [AXI_ADDR_WIDTH-1:0]  s_axi_araddr_i,
  input  logic [2:0]                  s_axi_arprot_i,
  input  logic                        s_axi_arvalid_i,
  output logic                        s_axi_arready_o,

  output logic [AXI_DATA_WIDTH-1:0]  s_axi_rdata_o,
  output logic [1:0]                  s_axi_rresp_o,
  output logic                        s_axi_rvalid_o,
  input  logic                        s_axi_rready_i,

  // SPI Interface
  output logic                        sck_o,
  output logic                        mosi_o,
  input  logic                        miso_i,
  output logic [3:0]                   cs_o
);

  // Register offsets
  localparam TXDATA_OFFSET = 12'h000;
  localparam RXDATA_OFFSET = 12'h004;
  localparam STATUS_OFFSET = 12'h008;
  localparam CTRL_OFFSET   = 12'h00C;
  localparam CLK_DIV_OFFSET = 12'h010;
  localparam CMD_OFFSET    = 12'h014;

  // Register addresses
  logic [11:0] reg_addr;
  assign reg_addr = s_axi_awaddr_i[11:0];

  // Registers
  logic [7:0]  txdata_reg;
  logic [7:0]  rxdata_reg;
  logic [2:0]  status_reg;  // [0]busy, [1]rx_valid, [2]ready
  logic [6:0]  ctrl_reg;    // [0]en, [1]cpol, [2]cpha, [3]ie, [5:4]cs_sel, [6]cs_en
  logic [CLK_DIV_WIDTH-1:0] clk_div_reg;
  logic        cmd_reg;     // [0]start

  // SPI Master instance
  spi_master #(
    .CLK_DIV_WIDTH(CLK_DIV_WIDTH)
  ) u_spi_master (
    .clk_i       (clk_i),
    .rstn_i      (rstn_i),
    .en_i        (ctrl_reg[0]),
    .cpol_i      (ctrl_reg[1]),
    .cpha_i      (ctrl_reg[2]),
    .clk_div_i   (clk_div_reg),
    .cs_sel_i    (ctrl_reg[5:4]),
    .cs_en_i     (ctrl_reg[6]),
    .start_i     (cmd_reg),
    .tx_data_i   (txdata_reg),
    .rx_data_o   (rxdata_reg),
    .busy_o      (status_reg[0]),
    .rx_valid_o  (status_reg[1]),
    .sck_o       (sck_o),
    .mosi_o      (mosi_o),
    .miso_i      (miso_i),
    .cs_o        (cs_o)
  );

  // Status register
  assign status_reg[2] = !status_reg[0];  // ready = !busy

  // AXI4-Lite Slave Bridge
  logic [AXI_ADDR_WIDTH-1:0]  awaddr_q;
  logic                        awvalid_q;
  logic [AXI_DATA_WIDTH-1:0]  wdata_q;
  logic [(AXI_DATA_WIDTH/8)-1:0] wstrb_q;
  logic                        wvalid_q;
  logic                        bvalid_q;
  logic [AXI_ADDR_WIDTH-1:0]  araddr_q;
  logic                        arvalid_q;
  logic                        rvalid_q;
  logic [AXI_DATA_WIDTH-1:0]  rdata_q;
  logic [1:0]                  rresp_q;

  // Write address channel
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      awaddr_q <= '0;
      awvalid_q <= 1'b0;
    end else begin
      if (s_axi_awvalid_i && s_axi_awready_o) begin
        awaddr_q <= s_axi_awaddr_i;
        awvalid_q <= 1'b1;
      end else if (bvalid_q && s_axi_bready_i) begin
        awvalid_q <= 1'b0;
      end
    end
  end

  assign s_axi_awready_o = !awvalid_q;

  // Write data channel
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      wdata_q <= '0;
      wstrb_q <= '0;
      wvalid_q <= 1'b0;
    end else begin
      if (s_axi_wvalid_i && s_axi_wready_o) begin
        wdata_q <= s_axi_wdata_i;
        wstrb_q <= s_axi_wstrb_i;
        wvalid_q <= 1'b1;
      end else if (bvalid_q && s_axi_bready_i) begin
        wvalid_q <= 1'b0;
      end
    end
  end

  assign s_axi_wready_o = !wvalid_q;

  // Write response channel
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      bvalid_q <= 1'b0;
    end else begin
      if (awvalid_q && wvalid_q && !bvalid_q) begin
        bvalid_q <= 1'b1;
      end else if (s_axi_bready_i) begin
        bvalid_q <= 1'b0;
      end
    end
  end

  assign s_axi_bvalid_o = bvalid_q;
  assign s_axi_bresp_o = 2'b00;  // OKAY

  // Read address channel
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      araddr_q <= '0;
      arvalid_q <= 1'b0;
    end else begin
      if (s_axi_arvalid_i && s_axi_arready_o) begin
        araddr_q <= s_axi_araddr_i;
        arvalid_q <= 1'b1;
      end else if (rvalid_q && s_axi_rready_i) begin
        arvalid_q <= 1'b0;
      end
    end
  end

  assign s_axi_arready_o = !arvalid_q;

  // Read data channel
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      rvalid_q <= 1'b0;
      rdata_q <= '0;
      rresp_q <= 2'b00;
    end else begin
      if (arvalid_q && !rvalid_q) begin
        rvalid_q <= 1'b1;
        case (araddr_q[11:0])
          TXDATA_OFFSET:  rdata_q <= {24'h0, txdata_reg};
          RXDATA_OFFSET:  rdata_q <= {24'h0, rxdata_reg};
          STATUS_OFFSET:  rdata_q <= {29'h0, status_reg};
          CTRL_OFFSET:    rdata_q <= {25'h0, ctrl_reg};
          CLK_DIV_OFFSET: rdata_q <= {24'h0, clk_div_reg};
          default:        rdata_q <= 32'h0;
        endcase
        rresp_q <= 2'b00;
      end else if (s_axi_rready_i) begin
        rvalid_q <= 1'b0;
      end
    end
  end

  assign s_axi_rvalid_o = rvalid_q;
  assign s_axi_rdata_o = rdata_q;
  assign s_axi_rresp_o = rresp_q;

  // Register write logic
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      txdata_reg <= '0;
      ctrl_reg <= 7'h0;
      clk_div_reg <= 8'd49;  // Default: 100MHz -> 1MHz SCK
      cmd_reg <= 1'b0;
    end else begin
      cmd_reg <= 1'b0;  // Self-clearing pulse
      if (awvalid_q && wvalid_q && s_axi_bready_i) begin
        case (awaddr_q[11:0])
          TXDATA_OFFSET: begin
            if (wstrb_q[0]) txdata_reg <= wdata_q[7:0];
          end
          STATUS_OFFSET: begin
            // Clear rx_valid on write
            if (wstrb_q[0]) status_reg[1] <= 1'b0;
          end
          CTRL_OFFSET: begin
            if (wstrb_q[0]) ctrl_reg[6:0] <= wdata_q[6:0];
          end
          CLK_DIV_OFFSET: begin
            if (wstrb_q[0]) clk_div_reg <= wdata_q[7:0];
          end
          CMD_OFFSET: begin
            if (wstrb_q[0]) cmd_reg <= wdata_q[0];
          end
        endcase
      end
    end
  end

endmodule
