// filepath: rtl/dqn/dqn_core.sv
// DQN Inference Core — FSM + Combinational MAC + LeakyReLU
// Ag: 4 -> 16 (LeakyReLU) -> 4
// Fixed-point: Q1.15 (sfix16_En15)
//
// Inference akisi:
//   S_IDLE -> S_FC1 (x16 noron, 1 cyc/noron) -> S_FC2 (x4 noronx4 grup)
//          -> S_ARGMAX -> S_DONE
//
// Her FC1 cycle'da: 4 combinational carpma + toplama + bias + ReLU -> hidden[j]
// Her FC2 cycle'da: 4 combinational carpma + toplama -> acc birikmesi, son grupta bias ekle
`timescale 1ns / 1ps

module dqn_core (
  input  logic                 clk_i,
  input  logic                 rstn_i,
  input  logic                 enable_i,
  input  logic                 start_i,       // tek cycle pulse
  input  logic                 soft_reset_i,   // tek cycle pulse

  // State giris vektoru (4 eleman, Q1.15)
  input  logic signed [15:0]   state_in_i [0:3],

  // FC1 agirliklari: fc1_w[input_idx][output_idx]
  input  logic signed [15:0]   fc1_w_i [0:3][0:15],
  // FC1 bias: fc1_b[neuron_idx]
  input  logic signed [15:0]   fc1_b_i [0:15],
  // FC2 agirliklari: fc2_w[input_idx][output_idx]
  input  logic signed [15:0]   fc2_w_i [0:15][0:3],
  // FC2 bias: fc2_b[neuron_idx]
  input  logic signed [15:0]   fc2_b_i [0:3],

  // Cikislar
  output logic signed [15:0]   q_val_o [0:3],
  output logic                 busy_o,
  output logic                 done_o,
  output logic [1:0]           argmax_o,
  output logic signed [15:0]   q_max_o,
  output logic [15:0]          cycle_cnt_o
);

  // ════════════════════════════════════════════════
  // LeakyReLU sabiti: alpha = 0.01
  // round(0.01 * 32768) = 328 = 0x0148
  // ════════════════════════════════════════════════
  localparam signed [15:0] LEAKY_ALPHA = 16'sh0148;

  // ════════════════════════════════════════════════
  // FSM durumlari
  // ════════════════════════════════════════════════
  typedef enum logic [2:0] {
    S_IDLE,
    S_FC1,
    S_FC2,
    S_ARGMAX,
    S_DONE
  } state_t;

  state_t fsm_state;

  // ════════════════════════════════════════════════
  // Sayaclar
  // ════════════════════════════════════════════════
  logic [3:0]  fc1_idx;
  logic [1:0]  fc2_neuron_idx;
  logic [1:0]  fc2_group_idx;
  logic [15:0] cycle_counter;

  // ════════════════════════════════════════════════
  // Dahili depolama - Vivado BRAM inference
  // ════════════════════════════════════════════════
  (* ram_style = "distributed" *) logic signed [15:0] hidden [0:15];
  logic signed [31:0] acc;

  (* ram_style = "distributed" *) logic signed [15:0] q_val_r [0:3];

  logic [1:0]         argmax_r;
  logic signed [15:0] q_max_r;
  logic done_r;

  // ════════════════════════════════════════════════
  // Combinational wire'lar (modul scope'de tanimla)
  // ════════════════════════════════════════════════
  logic signed [31:0] fc1_prod0, fc1_prod1, fc1_prod2, fc1_prod3;
  logic signed [31:0] fc1_sum;
  logic signed [15:0] fc1_q15;
  logic signed [15:0] fc1_biased;
  logic signed [31:0] fc1_relu_prod;
  logic signed [15:0] fc1_activated;

  logic [3:0]         fc2_base;
  logic signed [31:0] fc2_prod0, fc2_prod1, fc2_prod2, fc2_prod3;
  logic signed [31:0] fc2_sum;
  logic signed [15:0] fc2_q15;
  logic signed [31:0] fc2_new_acc;

  logic signed [15:0] argmax_max_val;
  logic [1:0]         argmax_max_idx;

  // ════════════════════════════════════════════════
  // FC1 Combinational Datapath
  // ════════════════════════════════════════════════
  always_comb begin
    fc1_prod0 = state_in_i[0] * fc1_w_i[0][fc1_idx];
    fc1_prod1 = state_in_i[1] * fc1_w_i[1][fc1_idx];
    fc1_prod2 = state_in_i[2] * fc1_w_i[2][fc1_idx];
    fc1_prod3 = state_in_i[3] * fc1_w_i[3][fc1_idx];

    fc1_sum    = fc1_prod0 + fc1_prod1 + fc1_prod2 + fc1_prod3;
    fc1_q15    = fc1_sum[30:15];
    fc1_biased = fc1_q15 + fc1_b_i[fc1_idx];

    // LeakyReLU
    fc1_relu_prod = fc1_biased * LEAKY_ALPHA;
    if (fc1_biased >= 16'sh0000)
      fc1_activated = fc1_biased;
    else
      fc1_activated = fc1_relu_prod[30:15];
  end

  // ════════════════════════════════════════════════
  // FC2 Combinational Datapath
  // ════════════════════════════════════════════════
  assign fc2_base = {fc2_group_idx, 2'b00};

  always_comb begin
    fc2_prod0 = hidden[fc2_base + 4'd0] * fc2_w_i[fc2_base + 4'd0][fc2_neuron_idx];
    fc2_prod1 = hidden[fc2_base + 4'd1] * fc2_w_i[fc2_base + 4'd1][fc2_neuron_idx];
    fc2_prod2 = hidden[fc2_base + 4'd2] * fc2_w_i[fc2_base + 4'd2][fc2_neuron_idx];
    fc2_prod3 = hidden[fc2_base + 4'd3] * fc2_w_i[fc2_base + 4'd3][fc2_neuron_idx];

    fc2_sum     = fc2_prod0 + fc2_prod1 + fc2_prod2 + fc2_prod3;
    fc2_q15     = fc2_sum[30:15];
    fc2_new_acc = acc + {{16{fc2_q15[15]}}, fc2_q15};
  end

  // ════════════════════════════════════════════════
  // Argmax Combinational
  // ════════════════════════════════════════════════
  always_comb begin
    argmax_max_val = q_val_r[0];
    argmax_max_idx = 2'd0;
    if (q_val_r[1] > argmax_max_val) begin argmax_max_val = q_val_r[1]; argmax_max_idx = 2'd1; end
    if (q_val_r[2] > argmax_max_val) begin argmax_max_val = q_val_r[2]; argmax_max_idx = 2'd2; end
    if (q_val_r[3] > argmax_max_val) begin argmax_max_val = q_val_r[3]; argmax_max_idx = 2'd3; end
  end

  // ════════════════════════════════════════════════
  // Cikis atamalari — genvar yerine dogrudan assign
  // ════════════════════════════════════════════════
  assign busy_o      = (fsm_state != S_IDLE) && (fsm_state != S_DONE);
  assign done_o      = done_r;
  assign argmax_o    = argmax_r;
  assign q_max_o     = q_max_r;
  assign cycle_cnt_o = cycle_counter;

  assign q_val_o[0]  = q_val_r[0];
  assign q_val_o[1]  = q_val_r[1];
  assign q_val_o[2]  = q_val_r[2];
  assign q_val_o[3]  = q_val_r[3];

  // ════════════════════════════════════════════════
  // FSM + Sequential Logic
  // ════════════════════════════════════════════════
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      fsm_state      <= S_IDLE;
      fc1_idx        <= 4'd0;
      fc2_neuron_idx <= 2'd0;
      fc2_group_idx  <= 2'd0;
      cycle_counter  <= 16'd0;
      acc            <= 32'sd0;
      done_r         <= 1'b0;
      argmax_r       <= 2'd0;
      q_max_r        <= 16'sh8000;
      for (int i = 0; i < 16; i++) hidden[i] <= 16'sh0000;
      for (int i = 0; i < 4; i++)  q_val_r[i] <= 16'sh0000;
    end else if (soft_reset_i) begin
      fsm_state      <= S_IDLE;
      fc1_idx        <= 4'd0;
      fc2_neuron_idx <= 2'd0;
      fc2_group_idx  <= 2'd0;
      cycle_counter  <= 16'd0;
      acc            <= 32'sd0;
      done_r         <= 1'b0;
      argmax_r       <= 2'd0;
      q_max_r        <= 16'sh8000;
    end else if (enable_i) begin
      case (fsm_state)
        S_IDLE: begin
          if (start_i) begin
            fsm_state      <= S_FC1;
            fc1_idx        <= 4'd0;
            fc2_neuron_idx <= 2'd0;
            fc2_group_idx  <= 2'd0;
            cycle_counter  <= 16'd0;
            acc            <= 32'sd0;
            done_r         <= 1'b0;
            argmax_r       <= 2'd0;
            q_max_r        <= 16'sh8000;
          end
        end

        S_FC1: begin
          hidden[fc1_idx] <= fc1_activated;
          cycle_counter   <= cycle_counter + 16'd1;

          if (fc1_idx == 4'd15) begin
            fsm_state      <= S_FC2;
            fc2_neuron_idx <= 2'd0;
            fc2_group_idx  <= 2'd0;
            acc            <= 32'sd0;
          end else begin
            fc1_idx <= fc1_idx + 4'd1;
          end
        end

        S_FC2: begin
          cycle_counter <= cycle_counter + 16'd1;

          if (fc2_group_idx == 2'd3) begin
            q_val_r[fc2_neuron_idx] <= fc2_new_acc[15:0] + fc2_b_i[fc2_neuron_idx];
            acc           <= 32'sd0;
            fc2_group_idx <= 2'd0;

            if (fc2_neuron_idx == 2'd3) begin
              fsm_state <= S_ARGMAX;
            end else begin
              fc2_neuron_idx <= fc2_neuron_idx + 2'd1;
            end
          end else begin
            acc           <= fc2_new_acc;
            fc2_group_idx <= fc2_group_idx + 2'd1;
          end
        end

        S_ARGMAX: begin
          argmax_r      <= argmax_max_idx;
          q_max_r       <= argmax_max_val;
          cycle_counter <= cycle_counter + 16'd1;
          fsm_state     <= S_DONE;
        end

        S_DONE: begin
          done_r <= 1'b1;
          if (start_i) begin
            fsm_state      <= S_FC1;
            fc1_idx        <= 4'd0;
            fc2_neuron_idx <= 2'd0;
            fc2_group_idx  <= 2'd0;
            cycle_counter  <= 16'd0;
            acc            <= 32'sd0;
            done_r         <= 1'b0;
            argmax_r       <= 2'd0;
            q_max_r        <= 16'sh8000;
          end
        end

        default: fsm_state <= S_IDLE;
      endcase
    end
  end

endmodule
