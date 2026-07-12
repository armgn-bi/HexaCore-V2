`timescale 1ns/1ps
//===================================================================
// tb_uart_monitor.sv
//   Captures UART_TXD_OUT from nexys_a7_top and prints ASCII chars
//   with simulation time – mimics a real terminal.
//===================================================================
module tb_uart_monitor;

  //-------------------------------------------------
  // Clock & Reset (100 MHz → 10 ns period)
  //-------------------------------------------------
    logic clk = 0;
    logic rstn;
     always #5 clk = ~clk;          // 10 ns period

    initial begin
    rstn = 0;
    #20 rstn = 1;                // release reset after 20 ns
    end

  //-------------------------------------------------
  // UART TX monitor (collect bits → bytes → ASCII)
  //-------------------------------------------------
    logic        uart_rx;          // wire from DUT
    logic [7:0]  rx_shift = 0;
    logic [3:0]  rx_bitcnt = 0;
    logic        rx_sample_tick;   // tick at middle of each bit
    logic [2:0]  baud_cnt = 0;
    localparam integer CLK_FREQ   = 100_000_000;   // 100 MHz
    localparam integer BAUD_RATE  = 115_200;
    localparam integer BAUD_TICK  = CLK_FREQ / BAUD_RATE; // 868.09 ≈ 868

    // Assign the DUT’s UART TX to our monitor
    assign uart_rx = nexys_a7_top_inst.UART_RXD_OUT;

    // Baud‑rate tick generator (sample at ~mid‑bit)
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
        baud_cnt   <= 0;
        rx_sample_tick <= 0;
        end else if (baud_cnt == BAUD_TICK-1) begin
        baud_cnt   <= 0;
        rx_sample_tick <= 1;
        end else begin
        baud_cnt   <= baud_cnt + 1;
        rx_sample_tick <= 0;
        end
    end

    // Shift‑register: sample UART line at the tick
    always @(posedge rx_sample_tick) begin
        if (!rstn) begin
        rx_shift   <= 0;
        rx_bitcnt  <= 0;
        end else begin
        rx_shift   <= {uart_rx, rx_shift[7:1]};
        rx_bitcnt  <= rx_bitcnt + 1;
        if (rx_bitcnt == 4'd10) begin   // 1 start + 8 data + 1 stop
            $display("[%0t] UART RX: %c (0x%02h)", $time, rx_shift, rx_shift);
            rx_shift   <= 0;
            rx_bitcnt  <= 0;
        end
        end
    end

    //-------------------------------------------------
    // DUT: Nexys A7 top-level wrapper
    //-------------------------------------------------
    nexys_a7_top nexys_a7_top_inst (
        .CLK100MHZ   (clk),
        .CPU_RESETN  (rstn),
        .UART_RXD_OUT(),        // output from DUT → monitored above
        .UART_TXD_IN (1'b0),    // idle high (no PC → FPGA traffic)
        .LED(),                 // leave unconnected – we don’t need them
        .SW  (4'b0),
        .JA1 (1'bz), .JA2 (1'bz), // I2C – not used in this test
        .JB1 (), .JB2 (), .JB3 (), .JB4_7 ()
    );

    //-------------------------------------------------
    // Memory initialization – point to the .mem files you already have
    //-------------------------------------------------
    // The top‑level does **not** contain the memory; the soc_top inside
    // does.  We therefore need to point the soc_top’s parameters at the
    // same files used elsewhere in the repository.
    // The easiest way is to let the soc_top read them via $readmemh
    // inside its own source – no extra work needed here.

    //-------------------------------------------------
    // Test control – stop after a reasonable idle period
    //-------------------------------------------------
    initial begin
        #200_000_000;   // 200 ms simulation time (plenty for a maze run)
        $display("\n=== UART MONITOR TEST FINISHED (timeout) ===");
        $finish;
    end

endmodule