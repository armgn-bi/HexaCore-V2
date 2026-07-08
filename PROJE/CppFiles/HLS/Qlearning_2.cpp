#include <iostream>
#include <vector>
#include <random>
#include <cmath>
#include <algorithm>
#include <deque>
#include <fstream>
#include <string>
#include <chrono>
#include <iomanip>
#include <set>

// =============================================================================
// VITIS HLS SETTINGS
// =============================================================================
#define MAX_SIZE 20
#define NUM_ACTIONS 4

// LFSR for Synthesizable Random Number Generation
unsigned int lfsr_rand(unsigned int& seed) {
    #pragma HLS INLINE
    unsigned int b = ((seed >> 0) ^ (seed >> 2) ^ (seed >> 3) ^ (seed >> 5)) & 1;
    seed = (seed >> 1) | (b << 31);
    return seed;
}

// Synthesizable Kernel
void q_learning_accel(int width, int height, int target_episodes, 
                      int grid[MAX_SIZE][MAX_SIZE], 
                      float q_table[MAX_SIZE][MAX_SIZE][NUM_ACTIONS]) {
    
    #pragma HLS INTERFACE m_axi port=grid bundle=gmem0
    #pragma HLS INTERFACE m_axi port=q_table bundle=gmem1
    #pragma HLS INTERFACE s_axilite port=width
    #pragma HLS INTERFACE s_axilite port=height
    #pragma HLS INTERFACE s_axilite port=target_episodes
    #pragma HLS INTERFACE s_axilite port=return

    // Local buffers for performance
    int local_grid[MAX_SIZE][MAX_SIZE];
    float local_q_table[MAX_SIZE][MAX_SIZE][NUM_ACTIONS];
    #pragma HLS ARRAY_PARTITION variable=local_q_table dim=3 complete
    
    // Initialize local memory
    LOAD_GRID_ROW: for(int i = 0; i < height; i++) {
        LOAD_GRID_COL: for(int j = 0; j < width; j++) {
            #pragma HLS PIPELINE II=1
            local_grid[i][j] = grid[i][j];
        }
    }

    LOAD_Q_ROW: for(int i = 0; i < height; i++) {
        LOAD_Q_COL: for(int j = 0; j < width; j++) {
            LOAD_Q_ACT: for(int k = 0; k < NUM_ACTIONS; k++) {
                #pragma HLS PIPELINE II=1
                local_q_table[i][j][k] = q_table[i][j][k];
            }
        }
    }

    unsigned int seed = 123456789;
    const float learning_rate = 0.1f;
    const float discount_factor = 0.99f;
    float epsilon = 1.0f;
    const float epsilon_decay = 0.995f;
    const float epsilon_min = 0.01f;

    // Fixed deltas: 0:Right, 1:Down, 2:Left, 3:Up
    const int dx[4] = {1, 0, -1, 0};
    const int dy[4] = {0, 1, 0, -1};

    EPISODE_LOOP: for (int episode = 0; episode < target_episodes; ++episode) {
        #pragma HLS LOOP_TRIPCOUNT min=100 max=5000
        
        int start_node = lfsr_rand(seed) % (width * height);
        int sx = start_node % width;
        int sy = start_node / width;
        
        // Simple scan for valid start if invalid (hardware friendly fallback)
        while(local_grid[sy][sx] == 1 || (sx == width-1 && sy == height-1)) {
           start_node = (start_node + 1) % (width * height);
           sx = start_node % width;
           sy = start_node / width;
        }

        int curr_x = sx;
        int curr_y = sy;
        int dest_x = width - 1;
        int dest_y = height - 1;

        int steps = 0;
        STEP_LOOP: while(steps < width * height) {
            #pragma HLS PIPELINE off 
            
            if (curr_x == dest_x && curr_y == dest_y) break;

            // 1. Choose Action
            int action = -1;
            unsigned int rand_val = lfsr_rand(seed);
            float rand_float = (float)(rand_val % 1000) / 1000.0f;

            bool can_move[4];
            int valid_count = 0;
            int valid_acts[4];

            // Check validity
            CHECK_VALID: for(int k=0; k<4; ++k) {
                #pragma HLS UNROLL
                int nx = curr_x + dx[k];
                int ny = curr_y + dy[k];
                if(nx >=0 && nx < width && ny >=0 && ny < height && local_grid[ny][nx] == 0) {
                    can_move[k] = true;
                    valid_acts[valid_count++] = k;
                } else {
                    can_move[k] = false;
                }
            }

            if (valid_count == 0) break; // Stuck

            if (rand_float < epsilon) {
                 // Explore
                 int ridx = lfsr_rand(seed) % valid_count;
                 action = valid_acts[ridx];
            } else {
                // Exploit
                float max_q = -1e9f;
                int best_a = valid_acts[0];
                
                FIND_MAX: for(int k=0; k<4; ++k) {
                    #pragma HLS UNROLL
                    if(can_move[k]) {
                        if(local_q_table[curr_y][curr_x][k] > max_q) {
                            max_q = local_q_table[curr_y][curr_x][k];
                            best_a = k;
                        }
                    }
                }
                action = best_a;
            }

            // 2. Move
            int next_x = curr_x + dx[action];
            int next_y = curr_y + dy[action];


            // 3. Reward
            float reward = -1.0f;
            bool done = false;
            if (next_x == dest_x && next_y == dest_y) {
                reward = 100.0f;
                done = true;
            }

            // 4. Update Q-Value
            float max_next_q = -1e9f;
            bool has_next_move = false;
            
            // Look ahead
            LOOKAHEAD: for(int k=0; k<4; ++k) {
                #pragma HLS UNROLL
                int nnx = next_x + dx[k];
                int nny = next_y + dy[k];
                if(nnx >=0 && nnx < width && nny >=0 && nny < height && local_grid[nny][nnx] == 0) {
                     if(local_q_table[next_y][next_x][k] > max_next_q) {
                         max_next_q = local_q_table[next_y][next_x][k];
                     }
                     has_next_move = true;
                }
            }
            if (!has_next_move) max_next_q = 0.0f; // Terminal or Stuck
            if (done) max_next_q = 0.0f;           // Terminal

            float current_q = local_q_table[curr_y][curr_x][action];
            local_q_table[curr_y][curr_x][action] = current_q + learning_rate * (reward + discount_factor * max_next_q - current_q);

            curr_x = next_x;
            curr_y = next_y;
            steps++;
        }

        // Decay Epsilon
        if (epsilon > epsilon_min) epsilon *= epsilon_decay;
    }

    // Write back
    STORE_Q_ROW: for(int i = 0; i < height; i++) {
        STORE_Q_COL: for(int j = 0; j < width; j++) {
            STORE_Q_ACT: for(int k = 0; k < NUM_ACTIONS; k++) {
                #pragma HLS PIPELINE II=1
                q_table[i][j][k] = local_q_table[i][j][k];
            }
        }
    }
}

// =============================================================================
// 0. UTILS (Modified)
// =============================================================================

// Simple struct to represent a point
struct Point {
    int x;
    int y;
    
    bool operator==(const Point& other) const {
        return x == other.x && y == other.y;
    }
    
    bool operator!=(const Point& other) const {
        return !(*this == other);
    }
    
    // For using Point in std::set/map
    bool operator<(const Point& other) const {
        if (x != other.x) return x < other.x;
        return y < other.y;
    }
};

