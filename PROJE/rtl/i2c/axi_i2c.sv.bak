// filepath: rtl/i2c/axi_i2c.sv
// AXI4-Lite I2C Master Controller
// Base: 0x4000_0200
`timescale 1ns / 1ps

module axi_i2c #(
  parameter AXI_ADDR_WIDTH = 32,
  parameter AXI_DATA_WIDTH = 32,
  parameter PRESCALE_WIDTH = 16
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

  // I2C Interface (open-drain)
  output logic                        sda_oe_o,
  output logic                        scl_oe_o,
  input  logic                        sda_i,
  input  logic                        scl_i
);

  // Register offsets
  localparam TXDATA_OFFSET  = 12'h000;
  localparam RXDATA_OFFSET  = 12'h004;
  localparam STATUS_OFFSET  = 12'h008;
  localparam CTRL_OFFSET    = 12'h00C;
  localparam PRESCALE_OFFSET = 12'h010;
  localparam CMD_OFFSET     = 12'h014;

  // Register addresses
  logic [11:0] reg_addr;
  assign reg_addr = s_axi_awaddr_i[11:0];

  // Registers
  logic [7:0]  txdata_reg;
  logic [7:0]  rxdata_reg;
  logic [4:0]  status_reg;  // [0]busy, [1]ack_err, [2]rx_valid, [3]cmd_ready, [4]arb_lost
  logic [1:0]  ctrl_reg;    // [0]en, [1]ie
  logic [PRESCALE_WIDTH-1:0] prescale_reg;
  logic [2:0]  cmd_reg;     // [2:0]command

  // I2C Master instance
  i2c_master #(
    .PRESCALE_WIDTH(PRESCALE_WIDTH)
  ) u_i2c_master (
    .clk_i        (clk_i),
    .rstn_i       (rstn_i),
    .en_i         (ctrl_reg[0]),
    .prescale_i   (prescale_reg),
    .cmd_i        (cmd_reg),
    .tx_data_i    (txdata_reg),
    .rx_data_o    (rxdata_reg),
    .busy_o       (status_reg[0]),
    .ack_err_o    (status_reg[1]),
    .rx_valid_o   (status_reg[2]),
    .cmd_ready_o  (status_reg[3]),
    .sda_oe_o     (sda_oe_o),
    .scl_oe_o     (scl_oe_o),
    .sda_i        (sda_i),
    .scl_i        (scl_i)
  );

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
      end else if (s_axi_bvalid_i && s_axi_bready_i) begin
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
      end else if (s_axi_bvalid_i && s_axi_bready_i) begin
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
      end else if (s_axi_rvalid_i && s_axi_rready_i) begin
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
          STATUS_OFFSET:  rdata_q <= {27'h0, status_reg};
          CTRL_OFFSET:    rdata_q <= {30'h0, ctrl_reg};
          PRESCALE_OFFSET: rdata_q <= {16'h0, prescale_reg};
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
      ctrl_reg <= 2'h0;
      prescale_reg <= 16'd249;  // Default: 100MHz -> 100kHz SCL
      cmd_reg <= 3'h0;
    end else begin
      cmd_reg <= 3'h0;  // Self-clearing pulse
      if (awvalid_q && wvalid_q && s_axi_bready_i) begin
        case (awaddr_q[11:0])
          TXDATA_OFFSET: begin
            if (wstrb_q[0]) txdata_reg <= wdata_q[7:0];
          end
          STATUS_OFFSET: begin
            // Clear ack_err on write
            if (wstrb_q[0]) status_reg[1] <= 1'b0;
          end
          CTRL_OFFSET: begin
            if (wstrb_q[0]) ctrl_reg[1:0] <= wdata_q[1:0];
          end
          PRESCALE_OFFSET: begin
            if (wstrb_q[0]) prescale_reg <= wdata_q[15:0];
          end
          CMD_OFFSET: begin
            if (wstrb_q[0]) cmd_reg <= wdata_q[2:0];
          end
        endcase
      end
    end
  end

endmodule
