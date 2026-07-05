// filepath: rtl/uart/axi_uart.sv
// AXI4-Lite UART Controller
// Base: 0x4000_0000
`timescale 1ns / 1ps

module axi_uart #(
  parameter AXI_ADDR_WIDTH = 32,
  parameter AXI_DATA_WIDTH = 32,
  parameter BAUD_DIV_WIDTH = 16
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

  // UART Interface
  output logic                        uart_tx_o,
  input  logic                        uart_rx_i,
  output logic                        uart_irq_o
);

  // Register offsets
  localparam TXDATA_OFFSET  = 12'h000;
  localparam RXDATA_OFFSET  = 12'h004;
  localparam STATUS_OFFSET  = 12'h008;
  localparam CTRL_OFFSET    = 12'h00C;
  localparam BAUD_DIV_OFFSET = 12'h010;

  // Register addresses
  logic [11:0] reg_addr;
  assign reg_addr = s_axi_awaddr_i[11:0];

  // Registers
  logic [7:0]  txdata_reg;
  logic [7:0]  rxdata_reg;
  logic [5:0]  status_reg;  // [0]tx_full, [1]tx_empty, [2]rx_full, [3]rx_empty, [4]frame_err, [5]overrun_err
  logic [3:0]  ctrl_reg;    // [0]tx_en, [1]rx_en, [2]tx_ie, [3]rx_ie
  logic [BAUD_DIV_WIDTH-1:0] baud_div_reg;

  // FIFO instances
  logic tx_fifo_full, tx_fifo_empty;
  logic tx_fifo_wr, tx_fifo_rd;
  logic [7:0] tx_fifo_data;

  logic rx_fifo_full, rx_fifo_empty;
  logic rx_fifo_wr, rx_fifo_rd;
  logic [7:0] rx_fifo_data;

  uart_fifo #(
    .DATA_WIDTH(8),
    .DEPTH(16)
  ) u_tx_fifo (
    .clk_i     (clk_i),
    .rstn_i    (rstn_i),
    .wr_en_i   (tx_fifo_wr),
    .wr_data_i (txdata_reg),
    .full_o    (tx_fifo_full),
    .rd_en_i   (tx_fifo_rd),
    .rd_data_o (tx_fifo_data),
    .empty_o   (tx_fifo_empty)
  );

  uart_fifo #(
    .DATA_WIDTH(8),
    .DEPTH(16)
  ) u_rx_fifo (
    .clk_i     (clk_i),
    .rstn_i    (rstn_i),
    .wr_en_i   (rx_fifo_wr),
    .wr_data_i (rx_fifo_data),
    .full_o    (rx_fifo_full),
    .rd_en_i   (rx_fifo_rd),
    .rd_data_o (rxdata_reg),
    .empty_o   (rx_fifo_empty)
  );

  // UART TX instance
  logic tx_start, tx_busy;
  uart_tx #(
    .BAUD_DIV_WIDTH(BAUD_DIV_WIDTH)
  ) u_uart_tx (
    .clk_i       (clk_i),
    .rstn_i      (rstn_i),
    .tx_en_i     (ctrl_reg[0]),
    .baud_div_i  (baud_div_reg),
    .tx_start_i  (tx_start),
    .tx_data_i   (tx_fifo_data),
    .tx_busy_o   (tx_busy),
    .uart_tx_o   (uart_tx_o)
  );

  // UART RX instance
  logic rx_valid, frame_err, overrun_err;
  uart_rx #(
    .BAUD_DIV_WIDTH(BAUD_DIV_WIDTH)
  ) u_uart_rx (
    .clk_i       (clk_i),
    .rstn_i      (rstn_i),
    .rx_en_i     (ctrl_reg[1]),
    .baud_div_i  (baud_div_reg),
    .uart_rx_i   (uart_rx_i),
    .rx_valid_o  (rx_valid),
    .rx_data_o   (rx_fifo_data),
    .frame_err_o (frame_err),
    .overrun_err_o (overrun_err)
  );

  // Status register
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      status_reg <= 6'b000110;  // tx_empty=1, rx_empty=1
    end else begin
      status_reg[0] <= tx_fifo_full;
      status_reg[1] <= tx_fifo_empty;
      status_reg[2] <= rx_fifo_full;
      status_reg[3] <= rx_fifo_empty;
      status_reg[4] <= status_reg[4] | frame_err;  // sticky
      status_reg[5] <= status_reg[5] | overrun_err;  // sticky
    end
  end

  // Clear sticky errors on write to STATUS
  logic status_write;
  assign status_write = s_axi_wvalid_i && s_axi_awvalid_i &&
                        (reg_addr == STATUS_OFFSET) && s_axi_awready_o;

  // FIFO control
  assign tx_fifo_wr = s_axi_wvalid_i && s_axi_awvalid_i &&
                       (reg_addr == TXDATA_OFFSET) && s_axi_awready_o && !tx_fifo_full;
  assign tx_fifo_rd = !tx_fifo_empty && !tx_busy;
  assign tx_start = !tx_fifo_empty && !tx_busy;

  assign rx_fifo_wr = rx_valid && !rx_fifo_full;
  assign rx_fifo_rd = s_axi_arvalid_i && s_axi_arready_o &&
                       (s_axi_araddr_i[11:0] == RXDATA_OFFSET) && !rx_fifo_empty;

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
          RXDATA_OFFSET:  rdata_q <= {24'h0, rxdata_reg};
          STATUS_OFFSET:  rdata_q <= {26'h0, status_reg};
          CTRL_OFFSET:    rdata_q <= {28'h0, ctrl_reg};
          BAUD_DIV_OFFSET: rdata_q <= {16'h0, baud_div_reg};
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
      ctrl_reg <= 4'h0;
      baud_div_reg <= 16'd53;  // Default: 100MHz -> 115200 baud
    end else begin
      if (awvalid_q && wvalid_q && s_axi_bready_i) begin
        case (awaddr_q[11:0])
          TXDATA_OFFSET: begin
            if (wstrb_q[0]) txdata_reg <= wdata_q[7:0];
          end
          STATUS_OFFSET: begin
            // Clear sticky errors on write
            if (wstrb_q[0]) begin
              status_reg[4] <= 1'b0;  // frame_err
              status_reg[5] <= 1'b0;  // overrun_err
            end
          end
          CTRL_OFFSET: begin
            if (wstrb_q[0]) ctrl_reg[3:0] <= wdata_q[3:0];
          end
          BAUD_DIV_OFFSET: begin
            if (wstrb_q[0]) baud_div_reg <= wdata_q[15:0];
          end
        endcase
      end
    end
  end

  // Interrupt generation
  assign uart_irq_o = (ctrl_reg[2] && tx_fifo_empty) || (ctrl_reg[3] && !rx_fifo_empty);

endmodule
