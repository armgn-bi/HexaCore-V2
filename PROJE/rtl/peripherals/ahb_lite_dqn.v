// filepath: C:\Users\DELL\Downloads\HexaChipsers-Core\Verilog Dosyalari\Cevre Birimleri\dqn\ahb_lite_dqn.v
// AHB-Lite DQN Accelerator Wrapper
// HexaChipsers-Core projesi için DQN modülü AHB-Lite slave olarak bağlanır
// Base Address: 0xF0000000

module ahb_lite_dqn (
    // Global Signals
    input  wire        HCLK,
    input  wire        HRESETn,

    // AHB-Lite Slave Interface
    input  wire        HSEL,
    input  wire [1:0]  HTRANS,
    input  wire        HWRITE,
    input  wire        HMASTLOCK,
    input  wire [2:0]  HSIZE,
    input  wire [2:0]  HBURST,
    input  wire [3:0]  HPROT,
    input  wire [31:0] HADDR,
    input  wire [31:0] HWDATA,
    input  wire        HREADY,
    output wire        HREADYOUT,
    output wire [31:0] HRDATA,
    output wire        HRESP
);

    // ════════════════════════════════════════════════
    // Register offsets
    // ════════════════════════════════════════════════
    localparam CTRL_OFFSET      = 12'h000;
    localparam STATUS_OFFSET    = 12'h004;
    localparam STATE_0_OFFSET   = 12'h008;
    localparam STATE_1_OFFSET   = 12'h00C;
    localparam STATE_2_OFFSET   = 12'h010;
    localparam STATE_3_OFFSET   = 12'h014;
    localparam QVAL_0_OFFSET    = 12'h018;
    localparam QVAL_1_OFFSET    = 12'h01C;
    localparam QVAL_2_OFFSET    = 12'h020;
    localparam QVAL_3_OFFSET    = 12'h024;
    localparam QVAL_MAX_OFFSET  = 12'h028;
    localparam WT_ADDR_OFFSET   = 12'h02C;
    localparam WT_DATA_OFFSET   = 12'h030;
    localparam CYCLE_CNT_OFFSET = 12'h034;
    localparam VERSION_OFFSET   = 12'h038;

    // ════════════════════════════════════════════════
    // Internal registers
    // ════════════════════════════════════════════════
    reg  [3:0]  ctrl_reg;        // [0]enable, [1]start, [2]soft_reset, [3]wt_load_mode
    reg  [5:0]  status_reg;      // [0]busy, [1]done, [2]wt_loaded, [5:4]argmax
    reg  [15:0] state_reg [0:3];
    reg  [15:0] qval_reg [0:3];
    reg  [15:0] qval_max_reg;
    reg  [7:0]  wt_addr_reg;
    reg  [15:0] wt_data_reg;
    reg  [15:0] cycle_cnt_reg;

    // ════════════════════════════════════════════════
    // DQN Core signals
    // ════════════════════════════════════════════════
    wire        dqn_enable;
    wire        dqn_start;
    wire        dqn_soft_reset;
    wire signed [15:0] dqn_state_in [0:3];
    wire signed [15:0] dqn_fc1_w [0:3][0:15];
    wire signed [15:0] dqn_fc1_b [0:15];
    wire signed [15:0] dqn_fc2_w [0:15][0:3];
    wire signed [15:0] dqn_fc2_b [0:3];
    wire signed [15:0] dqn_q_val [0:3];
    wire        dqn_busy;
    wire        dqn_done;
    wire [1:0] dqn_argmax;
    wire signed [15:0] dqn_q_max;
    wire [15:0] dqn_cycle_cnt;

    // ════════════════════════════════════════════════
    // Weight memory (148 x 16-bit)
    // ════════════════════════════════════════════════
    reg signed [15:0] weight_mem [0:147];

    // ════════════════════════════════════════════════
    // AHB-Lite state machine
    // ════════════════════════════════════════════════
    reg  [1:0] ahb_state;
    reg  [31:0] ahb_addr_reg;
    reg  [31:0] ahb_wdata_reg;
    reg         ahb_write_reg;
    reg  [2:0]  ahb_size_reg;
    reg         ahb_trans_reg;

    localparam S_IDLE  = 2'b00;
    localparam S_SETUP = 2'b01;
    localparam S_ACCESS = 2'b10;

    // ════════════════════════════════════════════════
    // DQN Core instance
    // ════════════════════════════════════════════════
    dqn_core u_dqn_core (
        .clk_i        (HCLK),
        .rstn_i       (HRESETn),
        .enable_i     (dqn_enable),
        .start_i      (dqn_start),
        .soft_reset_i (dqn_soft_reset),
        .state_in_i   (dqn_state_in),
        .fc1_w_i      (dqn_fc1_w),
        .fc1_b_i      (dqn_fc1_b),
        .fc2_w_i      (dqn_fc2_w),
        .fc2_b_i      (dqn_fc2_b),
        .q_val_o      (dqn_q_val),
        .busy_o       (dqn_busy),
        .done_o       (dqn_done),
        .argmax_o     (dqn_argmax),
        .q_max_o      (dqn_q_max),
        .cycle_cnt_o  (dqn_cycle_cnt)
    );

    // ════════════════════════════════════════════════
    // DQN Core signal connections
    // ════════════════════════════════════════════════
    assign dqn_enable     = ctrl_reg[0];
    assign dqn_start      = ctrl_reg[1];
    assign dqn_soft_reset = ctrl_reg[2];

    assign dqn_state_in[0] = state_reg[0];
    assign dqn_state_in[1] = state_reg[1];
    assign dqn_state_in[2] = state_reg[2];
    assign dqn_state_in[3] = state_reg[3];

    // FC1 weights: 64 weights (4 inputs x 16 neurons)
    // weight_mem[0:63] -> fc1_w[0:3][0:15]
    genvar i, j;
    generate
        for (i = 0; i < 4; i = i + 1) begin : FC1_W_GEN
            for (j = 0; j < 16; j = j + 1) begin : FC1_W_NEURON
                assign dqn_fc1_w[i][j] = weight_mem[i * 16 + j];
            end
        end
    endgenerate

    // FC1 biases: 16 biases
    assign dqn_fc1_b[0]  = weight_mem[64];
    assign dqn_fc1_b[1]  = weight_mem[65];
    assign dqn_fc1_b[2]  = weight_mem[66];
    assign dqn_fc1_b[3]  = weight_mem[67];
    assign dqn_fc1_b[4]  = weight_mem[68];
    assign dqn_fc1_b[5]  = weight_mem[69];
    assign dqn_fc1_b[6]  = weight_mem[70];
    assign dqn_fc1_b[7]  = weight_mem[71];
    assign dqn_fc1_b[8]  = weight_mem[72];
    assign dqn_fc1_b[9]  = weight_mem[73];
    assign dqn_fc1_b[10] = weight_mem[74];
    assign dqn_fc1_b[11] = weight_mem[75];
    assign dqn_fc1_b[12] = weight_mem[76];
    assign dqn_fc1_b[13] = weight_mem[77];
    assign dqn_fc1_b[14] = weight_mem[78];
    assign dqn_fc1_b[15] = weight_mem[79];

    // FC2 weights: 64 weights (16 inputs x 4 neurons)
    // weight_mem[80:143] -> fc2_w[0:15][0:3]
    generate
        for (i = 0; i < 16; i = i + 1) begin : FC2_W_GEN
            assign dqn_fc2_w[i][0] = weight_mem[80 + i * 4 + 0];
            assign dqn_fc2_w[i][1] = weight_mem[80 + i * 4 + 1];
            assign dqn_fc2_w[i][2] = weight_mem[80 + i * 4 + 2];
            assign dqn_fc2_w[i][3] = weight_mem[80 + i * 4 + 3];
        end
    endgenerate

    // FC2 biases: 4 biases
    assign dqn_fc2_b[0] = weight_mem[144];
    assign dqn_fc2_b[1] = weight_mem[145];
    assign dqn_fc2_b[2] = weight_mem[146];
    assign dqn_fc2_b[3] = weight_mem[147];

    // ════════════════════════════════════════════════
    // Status register update
    // ════════════════════════════════════════════════
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            status_reg <= 6'h00;
        end else begin
            status_reg[0] <= dqn_busy;
            status_reg[1] <= status_reg[1] | dqn_done;  // sticky done
            status_reg[2] <= (wt_addr_reg == 8'd147);  // wt_loaded when last address written
            status_reg[5:4] <= dqn_argmax;
        end
    end

    // ════════════════════════════════════════════════
    // Q-value register update
    // ════════════════════════════════════════════════
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            qval_reg[0] <= 16'h0000;
            qval_reg[1] <= 16'h0000;
            qval_reg[2] <= 16'h0000;
            qval_reg[3] <= 16'h0000;
        end else if (dqn_done) begin
            qval_reg[0] <= dqn_q_val[0];
            qval_reg[1] <= dqn_q_val[1];
            qval_reg[2] <= dqn_q_val[2];
            qval_reg[3] <= dqn_q_val[3];
        end
    end

    // ════════════════════════════════════════════════
    // Q-max register update
    // ════════════════════════════════════════════════
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            qval_max_reg <= 16'h8000;
        end else if (dqn_done) begin
            qval_max_reg <= dqn_q_max;
        end
    end

    // ════════════════════════════════════════════════
    // Cycle counter register update
    // ════════════════════════════════════════════════
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            cycle_cnt_reg <= 16'h0000;
        end else if (dqn_done) begin
            cycle_cnt_reg <= dqn_cycle_cnt;
        end
    end

    // ════════════════════════════════════════════════
    // AHB-Lite state machine
    // ════════════════════════════════════════════════
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            ahb_state <= S_IDLE;
            ahb_addr_reg <= 32'h00000000;
            ahb_wdata_reg <= 32'h00000000;
            ahb_write_reg <= 1'b0;
            ahb_size_reg <= 3'b000;
            ahb_trans_reg <= 2'b00;
        end else begin
            case (ahb_state)
                S_IDLE: begin
                    if (HSEL && HTRANS[1]) begin
                        ahb_state <= S_SETUP;
                        ahb_addr_reg <= HADDR;
                        ahb_wdata_reg <= HWDATA;
                        ahb_write_reg <= HWRITE;
                        ahb_size_reg <= HSIZE;
                        ahb_trans_reg <= HTRANS;
                    end
                end

                S_SETUP: begin
                    ahb_state <= S_ACCESS;
                end

                S_ACCESS: begin
                    ahb_state <= S_IDLE;
                end

                default: ahb_state <= S_IDLE;
            endcase
        end
    end

    // ════════════════════════════════════════════════
    // Register write logic
    // ════════════════════════════════════════════════
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            ctrl_reg <= 4'h0;
            state_reg[0] <= 16'h0000;
            state_reg[1] <= 16'h0000;
            state_reg[2] <= 16'h0000;
            state_reg[3] <= 16'h0000;
            wt_addr_reg <= 8'h00;
            wt_data_reg <= 16'h0000;
        end else if (ahb_state == S_ACCESS && ahb_write_reg) begin
            case (ahb_addr_reg[11:0])
                CTRL_OFFSET: begin
                    if (ahb_size_reg == 3'b010) begin  // Word access
                        ctrl_reg <= ahb_wdata_reg[3:0];
                    end
                end

                STATE_0_OFFSET: begin
                    if (ahb_size_reg == 3'b010) begin
                        state_reg[0] <= ahb_wdata_reg[15:0];
                    end
                end

                STATE_1_OFFSET: begin
                    if (ahb_size_reg == 3'b010) begin
                        state_reg[1] <= ahb_wdata_reg[15:0];
                    end
                end

                STATE_2_OFFSET: begin
                    if (ahb_size_reg == 3'b010) begin
                        state_reg[2] <= ahb_wdata_reg[15:0];
                    end
                end

                STATE_3_OFFSET: begin
                    if (ahb_size_reg == 3'b010) begin
                        state_reg[3] <= ahb_wdata_reg[15:0];
                    end
                end

                WT_ADDR_OFFSET: begin
                    if (ahb_size_reg == 3'b010) begin
                        wt_addr_reg <= ahb_wdata_reg[7:0];
                    end
                end

                WT_DATA_OFFSET: begin
                    if (ahb_size_reg == 3'b010) begin
                        weight_mem[wt_addr_reg] <= ahb_wdata_reg[15:0];
                        // Auto-increment wt_addr
                        if (wt_addr_reg < 8'd147) begin
                            wt_addr_reg <= wt_addr_reg + 8'd1;
                        end
                    end
                end

                STATUS_OFFSET: begin
                    // Clear sticky done on write
                    if (ahb_size_reg == 3'b010) begin
                        status_reg[1] <= 1'b0;
                    end
                end
            endcase
        end
    end

    // ════════════════════════════════════════════════
    // Read data multiplexer
    // ════════════════════════════════════════════════
    reg [31:0] hrdata_reg;

    always @(*) begin
        case (ahb_addr_reg[11:0])
            CTRL_OFFSET:      hrdata_reg = {28'h0, ctrl_reg};
            STATUS_OFFSET:    hrdata_reg = {26'h0, status_reg};
            STATE_0_OFFSET:   hrdata_reg = {16'h0, state_reg[0]};
            STATE_1_OFFSET:   hrdata_reg = {16'h0, state_reg[1]};
            STATE_2_OFFSET:   hrdata_reg = {16'h0, state_reg[2]};
            STATE_3_OFFSET:   hrdata_reg = {16'h0, state_reg[3]};
            QVAL_0_OFFSET:    hrdata_reg = {16'h0, qval_reg[0]};
            QVAL_1_OFFSET:    hrdata_reg = {16'h0, qval_reg[1]};
            QVAL_2_OFFSET:    hrdata_reg = {16'h0, qval_reg[2]};
            QVAL_3_OFFSET:    hrdata_reg = {16'h0, qval_reg[3]};
            QVAL_MAX_OFFSET:  hrdata_reg = {16'h0, qval_max_reg};
            WT_ADDR_OFFSET:   hrdata_reg = {24'h0, wt_addr_reg};
            WT_DATA_OFFSET:   hrdata_reg = {16'h0, weight_mem[wt_addr_reg]};
            CYCLE_CNT_OFFSET: hrdata_reg = {16'h0, cycle_cnt_reg};
            VERSION_OFFSET:   hrdata_reg = 32'h44514E01;  // "DQN" + v1
            default:          hrdata_reg = 32'h00000000;
        endcase
    end

    // ════════════════════════════════════════════════
    // AHB-Lite outputs
    // ════════════════════════════════════════════════
    assign HREADYOUT = (ahb_state == S_IDLE) || (ahb_state == S_ACCESS);
    assign HRDATA    = (ahb_state == S_ACCESS && !ahb_write_reg) ? hrdata_reg : 32'h00000000;
    assign HRESP     = 1'b0;  // OKAY

endmodule
