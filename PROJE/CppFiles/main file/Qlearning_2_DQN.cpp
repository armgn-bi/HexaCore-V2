
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
// 0. UTILS
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

// PPM Image Writer to replace Matplotlib
void save_ppm(const std::string& filename, int width, int height, 
              const std::vector<std::vector<int>>& grid, 
              const std::vector<Point>& path) {
    std::ofstream ofs(filename);
    if (!ofs) {
        std::cerr << "Error: Could not open " << filename << " for writing." << std::endl;
        return;
    }

    // P3 format (ASCII RGB)
    ofs << "P3\n" << width * 20 << " " << height * 20 << "\n255\n";

    // Create a visual grid (scaling up by 20x for visibility)
    // 0 = Empty (White), 1 = Obstacle (Black)
    // Path = Red
    // Start = Green, End = Blue

    std::set<Point> path_set(path.begin(), path.end());
    Point start = path.front();
    Point end = path.back();

    for (int y = 0; y < height * 20; ++y) {
        for (int x = 0; x < width * 20; ++x) {
            int grid_x = x / 20;
            int grid_y = y / 20;
            
            Point p = {grid_x, grid_y};
            
            int r, g, b;
            
            if (p == start) {
                r = 0; g = 255; b = 0; // Green
            } else if (p == end) {
                r = 0; g = 0; b = 255; // Blue
            } else if (path_set.count(p)) {
                 r = 255; g = 0; b = 0; // Red
            } else if (grid[grid_y][grid_x] == 1) {
                r = 0; g = 0; b = 0; // Black (Obstacle)
            } else {
                r = 255; g = 255; b = 255; // White (Empty)
            }
            
            ofs << r << " " << g << " " << b << " ";
        }
        ofs << "\n";
    }
    
    std::cout << "Plot saved to " << filename << " (PPM format)" << std::endl;
}

// =============================================================================
// 1. OPTIMIZED MAZE SYSTEM
// =============================================================================

class PerfectMaze {
public:
    int width;
    int height;
    std::vector<std::vector<int>> grid;
    Point start_pos;
    Point end_pos;
    // valid_actions[y][x] contains list of actions (0:Right, 1:Down, 2:Left, 3:Up)
    std::vector<std::vector<std::vector<int>>> valid_actions;

    PerfectMaze(int w = 15, int h = 15, double obstacle_density = 0.1) 
        : width(w), height(h) {
        grid.resize(height, std::vector<int>(width, 0));
        start_pos = {0, 0};
        end_pos = {width - 1, height - 1};
        valid_actions.resize(height, std::vector<std::vector<int>>(width));
        
        generate_perfect_maze(obstacle_density);
        precompute_actions();
    }

    const std::vector<int>& get_possible_actions(int x, int y) const {
        return valid_actions[y][x];
    }

    bool is_valid(int x, int y) const {
        return x >= 0 && x < width && y >= 0 && y < height && grid[y][x] == 0;
    }

private:
    void generate_perfect_maze(double density) {
        // Clear grid
        for(auto& row : grid) std::fill(row.begin(), row.end(), 0);

        int n_obstacles = static_cast<int>(width * height * density);
        std::vector<int> indices(width * height);
        for(int i=0; i < width * height; ++i) indices[i] = i;

        // Shuffle indices
        unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();
        std::mt19937 g(seed);
        std::shuffle(indices.begin(), indices.end(), g);

        int count = 0;
        for (int idx : indices) {
            if (count >= n_obstacles) break;
            
            int y = idx / width;
            int x = idx % width;
            
            if ((x == start_pos.x && y == start_pos.y) || (x == end_pos.x && y == end_pos.y)) {
                continue;
            }
            
            grid[y][x] = 1;
            count++;
        }

        ensure_connectivity();
    }

    void ensure_connectivity() {
        while (true) {
            std::vector<std::vector<bool>> visited(height, std::vector<bool>(width, false));
            std::deque<Point> queue;
            
            queue.push_back(start_pos);
            visited[start_pos.y][start_pos.x] = true;
            
            int reachable_count = 0;
            
            int dx[] = {0, 1, 0, -1};
            int dy[] = {1, 0, -1, 0};
            
            while (!queue.empty()) {
                Point p = queue.front();
                queue.pop_front();
                reachable_count++;
                
                for (int i = 0; i < 4; ++i) {
                    int nx = p.x + dx[i];
                    int ny = p.y + dy[i];
                    
                    if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                        if (!visited[ny][nx] && grid[ny][nx] == 0) {
                            visited[ny][nx] = true;
                            queue.push_back({nx, ny});
                        }
                    }
                }
            }
            
            int total_empty = 0;
            for(const auto& row : grid) {
                for(int cell : row) {
                    if (cell == 0) total_empty++;
                }
            }
            
            if (reachable_count == total_empty) break;
            
            // Find unreachable cells
            std::vector<Point> unreachable;
            for (int y = 0; y < height; ++y) {
                for (int x = 0; x < width; ++x) {
                    if (grid[y][x] == 0 && !visited[y][x]) {
                        unreachable.push_back({x, y});
                    }
                }
            }
            
            if (unreachable.empty()) break;
            
            // Remove random obstacles
            std::vector<Point> obstacles;
            for (int y = 0; y < height; ++y) {
                for (int x = 0; x < width; ++x) {
                    if (grid[y][x] == 1) obstacles.push_back({x, y});
                }
            }
            
            if (!obstacles.empty()) {
                unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();
                std::mt19937 g(seed);
                std::shuffle(obstacles.begin(), obstacles.end(), g);
                
                int remove_count = std::min((int)obstacles.size(), 5);
                for (int i = 0; i < remove_count; ++i) {
                    grid[obstacles[i].y][obstacles[i].x] = 0;
                }
            } else {
                break;
            }
        }
    }

    void precompute_actions() {
        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                if (grid[y][x] == 1) continue;
                
                std::vector<int> actions;
                // 0:Right, 1:Down, 2:Left, 3:Up
                // Right
                if (x + 1 < width && grid[y][x + 1] == 0) actions.push_back(0);
                // Down
                if (y + 1 < height && grid[y + 1][x] == 0) actions.push_back(1);
                // Left
                if (x - 1 >= 0 && grid[y][x - 1] == 0) actions.push_back(2);
                // Up
                if (y - 1 >= 0 && grid[y - 1][x] == 0) actions.push_back(3);
                
                valid_actions[y][x] = actions;
            }
        }
    }
};

// =============================================================================
// 2. NEURAL NETWORK FROM SCRATCH
// =============================================================================

// Simple Matrix/Vector typedefs
typedef std::vector<float> Vector1D;
typedef std::vector<std::vector<float>> Vector2D;

class DenseLayer {
public:
    int input_size;
    int output_size;
    Vector2D weights;
    Vector1D biases;

    // Adam optimizer parameters
    Vector2D m_w, v_w;
    Vector1D m_b, v_b;
    float beta1 = 0.9f;
    float beta2 = 0.999f;
    float epsilon = 1e-8f;
    int t = 0; // timestep for adam

    // For backprop
    Vector1D input;
    Vector1D output;
    Vector2D dW; // gradients
    Vector1D db;

    DenseLayer() {}
    DenseLayer(int in_size, int out_size) : input_size(in_size), output_size(out_size) {
        weights.resize(in_size, Vector1D(out_size));
        biases.resize(out_size, 0.0f);
        m_w.resize(in_size, Vector1D(out_size, 0.0f));
        v_w.resize(in_size, Vector1D(out_size, 0.0f));
        m_b.resize(out_size, 0.0f);
        v_b.resize(out_size, 0.0f);

        dW.resize(in_size, Vector1D(out_size, 0.0f));
        db.resize(out_size, 0.0f);

        // Kaiming Initialization (He init) - better for ReLU family
        unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();
        std::mt19937 rng(seed);
        std::normal_distribution<float> dist(0.0f, std::sqrt(2.0f / in_size));

        for(int i = 0; i < in_size; ++i) {
            for(int j = 0; j < out_size; ++j) {
                weights[i][j] = dist(rng);
            }
        }
    }

    // Forward pass: Y = X * W + b
    const Vector1D& forward(const Vector1D& in_array) {
        input = in_array;
        output.assign(output_size, 0.0f);

        for(int j = 0; j < output_size; ++j) {
            for(int i = 0; i < input_size; ++i) {
                output[j] += input[i] * weights[i][j];
            }
            output[j] += biases[j];
        }
        return output;
    }

    // Backward pass: computing dW, db, and returning dX
    Vector1D backward(const Vector1D& d_out) {
        // dX = d_out * W^T
        Vector1D d_in(input_size, 0.0f);
        
        for(int i = 0; i < input_size; ++i) {
            for(int j = 0; j < output_size; ++j) {
                dW[i][j] += input[i] * d_out[j]; // Accumulating gradients for batch
                d_in[i] += d_out[j] * weights[i][j];
            }
        }
        
        for(int j = 0; j < output_size; ++j) {
            db[j] += d_out[j];
        }

        return d_in;
    }

    // Clear accumulated gradients
    void zero_grad() {
        for(int i = 0; i < input_size; ++i) {
            std::fill(dW[i].begin(), dW[i].end(), 0.0f);
        }
        std::fill(db.begin(), db.end(), 0.0f);
    }

    // Update weights using Adam
    void update_weights(float lr, int batch_size) {
        t++;
        float alpha_t = lr * std::sqrt(1.0f - std::pow(beta2, t)) / (1.0f - std::pow(beta1, t));

        for(int i = 0; i < input_size; ++i) {
            for(int j = 0; j < output_size; ++j) {
                float grad = dW[i][j] / batch_size;
                m_w[i][j] = beta1 * m_w[i][j] + (1.0f - beta1) * grad;
                v_w[i][j] = beta2 * v_w[i][j] + (1.0f - beta2) * grad * grad;
                weights[i][j] -= alpha_t * m_w[i][j] / (std::sqrt(v_w[i][j]) + epsilon);
            }
        }

        for(int j = 0; j < output_size; ++j) {
            float grad = db[j] / batch_size;
            m_b[j] = beta1 * m_b[j] + (1.0f - beta1) * grad;
            v_b[j] = beta2 * v_b[j] + (1.0f - beta2) * grad * grad;
            biases[j] -= alpha_t * m_b[j] / (std::sqrt(v_b[j]) + epsilon);
        }
    }
    
    // Copy weights from another layer (for Target Network sync)
    void copy_weights_from(const DenseLayer& other) {
        weights = other.weights;
        biases = other.biases;
    }
};

// Activation Functions
class LeakyReLU {
public:
    float alpha = 0.01f;
    Vector1D input;

    const Vector1D& forward(const Vector1D& in_array) {
        input = in_array;
        output.resize(input.size());
        for(size_t i = 0; i < input.size(); ++i) {
            output[i] = input[i] > 0 ? input[i] : alpha * input[i];
        }
        return output;
    }

    Vector1D backward(const Vector1D& d_out) {
        Vector1D d_in(d_out.size());
        for(size_t i = 0; i < input.size(); ++i) {
            d_in[i] = d_out[i] * (input[i] > 0 ? 1.0f : alpha);
        }
        return d_in;
    }

private:
    Vector1D output;
};

// The Deep Q-Network
class DQN {
public:
    DenseLayer fc1;
    LeakyReLU act1;
    DenseLayer fc2;
    LeakyReLU act2;
    DenseLayer fc3;

    DQN() {}
    DQN(int input_dim, int hidden_dim, int output_dim) {
        fc1 = DenseLayer(input_dim, hidden_dim);
        fc2 = DenseLayer(hidden_dim, hidden_dim);
        fc3 = DenseLayer(hidden_dim, output_dim);
    }

    Vector1D forward(const Vector1D& state) {
        Vector1D x = fc1.forward(state);
        x = act1.forward(x);
        x = fc2.forward(x);
        x = act2.forward(x);
        x = fc3.forward(x);
        return x;
    }

    void backward(const Vector1D& d_out) {
        Vector1D d_in = fc3.backward(d_out);
        d_in = act2.backward(d_in);
        d_in = fc2.backward(d_in);
        d_in = act1.backward(d_in);
        fc1.backward(d_in);
    }

    void zero_grad() {
        fc1.zero_grad();
        fc2.zero_grad();
        fc3.zero_grad();
    }

    void update_weights(float lr, int batch_size) {
        fc1.update_weights(lr, batch_size);
        fc2.update_weights(lr, batch_size);
        fc3.update_weights(lr, batch_size);
    }

    void copy_weights_from(const DQN& other) {
        fc1.copy_weights_from(other.fc1);
        fc2.copy_weights_from(other.fc2);
        fc3.copy_weights_from(other.fc3);
    }
};

// =============================================================================
// 3. OPTIMIZED SOLVER (DEEP Q-LEARNING)
// =============================================================================

struct Experience {
    Vector1D state;
    int action;
    float reward;
    Vector1D next_state;
    bool done;
};

class ReplayBuffer {
public:
    std::vector<Experience> buffer;
    size_t capacity;
    size_t position;

    ReplayBuffer(size_t cap) : capacity(cap), position(0) {}

    void push(const Vector1D& state, int action, float reward, const Vector1D& next_state, bool done) {
        if (buffer.size() < capacity) {
            buffer.push_back({state, action, reward, next_state, done});
        } else {
            buffer[position] = {state, action, reward, next_state, done};
            position = (position + 1) % capacity;
        }
    }

    std::vector<Experience> sample(size_t batch_size, std::mt19937& rng) {
        std::vector<Experience> batch;
        std::uniform_int_distribution<size_t> dist(0, buffer.size() - 1);
        for (size_t i = 0; i < batch_size; ++i) {
            batch.push_back(buffer[dist(rng)]);
        }
        return batch;
    }

    size_t size() const {
        return buffer.size();
    }
};

class DQNSolver {
public:
    PerfectMaze& maze;
    float gamma;
    float epsilon;
    float epsilon_min;
    float epsilon_decay;
    float lr = 0.001f;
    size_t batch_size = 64;
    int target_update_freq = 100;
    int steps_done = 0;

    DQN main_network;
    DQN target_network;
    ReplayBuffer replay_buffer;

    // dx/dy for actions 0:Right, 1:Down, 2:Left, 3:Up
    const int dx[4] = {1, 0, -1, 0};
    const int dy[4] = {0, 1, 0, -1};

    std::mt19937 rng;

    DQNSolver(PerfectMaze& m, float discount_factor = 0.99f, float exploration_rate = 1.0f)
        : maze(m), gamma(discount_factor), epsilon(exploration_rate),
          replay_buffer(50000) { // Capacity of 50000
          
        epsilon_min = 0.05f; // keep minimal exploration
        epsilon_decay = 0.9995f; // Even Slower decay for DQN

        // Input: normalized cx, cy, tx, ty (4) -> Output: Q-values (4)
        main_network = DQN(4, 128, 4);
        target_network = DQN(4, 128, 4);
        target_network.copy_weights_from(main_network);

        unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();
        rng.seed(seed);
    }

    Vector1D get_state(int x, int y, int tx, int ty) {
        return {
            (float)x / maze.width,
            (float)y / maze.height,
            (float)tx / maze.width,
            (float)ty / maze.height
        };
    }

    int get_action(int x, int y, int tx, int ty) {
        const auto& possible_actions = maze.get_possible_actions(x, y);
        if (possible_actions.empty()) return -1;
        
        std::uniform_real_distribution<float> dist(0.0f, 1.0f);
        
        // Epsilon-greedy
        if (dist(rng) < epsilon) {
            std::uniform_int_distribution<int> action_dist(0, possible_actions.size() - 1);
            return possible_actions[action_dist(rng)];
        }
        
        Vector1D state = get_state(x, y, tx, ty);
        Vector1D q_values = main_network.forward(state);

        float max_q = -1e9f;
        std::vector<int> best_actions;
        
        // Only select from valid actions!
        for (int action : possible_actions) {
            float q = q_values[action];
            if (q > max_q) {
                max_q = q;
                best_actions.clear();
                best_actions.push_back(action);
            } else if (std::abs(q - max_q) < 1e-6f) {
                best_actions.push_back(action);
            }
        }
        
        if (best_actions.empty()) return possible_actions[0];
        
        std::uniform_int_distribution<int> best_dist(0, best_actions.size() - 1);
        return best_actions[best_dist(rng)];
    }

    void remember(const Vector1D& state, int action, float reward, const Vector1D& next_state, bool done) {
        replay_buffer.push(state, action, reward, next_state, done);
    }

    void replay() {
        if (replay_buffer.size() < batch_size) return;

        auto mini_batch = replay_buffer.sample(batch_size, rng);
        
        main_network.zero_grad();
        float total_loss = 0.0f;

        for (const auto& exp : mini_batch) {
            // Forward pass for current state
            Vector1D current_q = main_network.forward(exp.state);
            
            float max_next_q = 0.0f;
            if (!exp.done) {
                Vector1D next_q = target_network.forward(exp.next_state);
                // Unrestricted max pooling over next q-values (simplification)
                max_next_q = *std::max_element(next_q.begin(), next_q.end());
            }

            float target_q = exp.reward + gamma * max_next_q;
            
            // MSE Loss Gradient w.r.t specific action output
            Vector1D d_out(4, 0.0f);
            
            // Output gradient = 2 * (predicted - target)
            float diff = current_q[exp.action] - target_q;
            d_out[exp.action] = 2.0f * diff; // Derivative of MSE
            
            total_loss += diff * diff;

            // Backward pass
            main_network.backward(d_out);
        }

        // Apply gradients
        main_network.update_weights(lr, batch_size);

        steps_done++;
        if (steps_done % target_update_freq == 0) {
            target_network.copy_weights_from(main_network);
        }
    }

    void decay_epsilon() {
        epsilon = std::max(epsilon_min, epsilon * epsilon_decay);
    }
};

// =============================================================================
// 4. HIGH-PERFORMANCE TRAINING LOOP
// =============================================================================

std::vector<float> train_agent(PerfectMaze& maze, DQNSolver& agent, int episodes = 1000) {
    std::cout << "Starting Training: " << episodes << " episodes" << std::endl;
    auto start_time = std::chrono::high_resolution_clock::now();
    
    std::vector<float> history_rewards;
    std::vector<int> history_steps;
    
    int width = maze.width;
    int height = maze.height;
    
    std::mt19937 rng;
    unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();
    rng.seed(seed);
    std::uniform_int_distribution<int> w_dist(0, width - 1);
    std::uniform_int_distribution<int> h_dist(0, height - 1);

    for (int episode = 0; episode < episodes; ++episode) {
        int sx, sy, tx, ty;
        while (true) {
            sx = w_dist(rng);
            sy = h_dist(rng);
            tx = width - 1;
            ty = height - 1;
            
            if (maze.grid[sy][sx] == 0 && maze.grid[ty][tx] == 0 && (sx != tx || sy != ty)) {
                break;
            }
        }
        
        int cx = sx;
        int cy = sy;
        float total_reward = 0;
        int steps = 0;
        int max_steps = width * height * 2; // give agent more time to find path
        bool done = false;
        
        while (steps < max_steps) {
            int action = agent.get_action(cx, cy, tx, ty);
            if (action == -1) break;
            
            int nx = cx + agent.dx[action];
            int ny = cy + agent.dy[action];
            
            float reward;
            if (nx == tx && ny == ty) {
                reward = 100.0f;
                done = true;
            } else if (maze.grid[ny][nx] == 1) { // Hit wall implicitly handled by possible_actions but just in case
                reward = -5.0f;
                done = false;
            } else {
                // Shaping reward based on distance to target can help DQN significantly
                float old_dist = std::abs(tx - cx) + std::abs(ty - cy);
                float new_dist = std::abs(tx - nx) + std::abs(ty - ny);
                
                if (new_dist < old_dist) {
                    reward = -0.1f; // Closer
                } else {
                    reward = -1.0f; // Further away
                }
                
                done = false;
            }
            
            Vector1D state = agent.get_state(cx, cy, tx, ty);
            Vector1D next_state = agent.get_state(nx, ny, tx, ty);

            // Store experience
            agent.remember(state, action, reward, next_state, done);

            // Train on mini-batch
            agent.replay();
            
            cx = nx;
            cy = ny;
            total_reward += reward;
            steps++;
            
            if (done) break;
        }
        
        agent.decay_epsilon();
        history_steps.push_back(steps);
        history_rewards.push_back(total_reward);
        
        if ((episode + 1) % 100 == 0) {
            float avg_steps = 0;
            int count = 0;
            for (int i = std::max(0, (int)history_steps.size() - 100); i < history_steps.size(); ++i) {
                avg_steps += history_steps[i];
                count++;
            }
            if (count > 0) avg_steps /= count;
            
            std::cout << "Episode " << std::setw(5) << episode + 1 
                      << " | Avg Steps: " << std::fixed << std::setprecision(1) << avg_steps 
                      << " | Epsilon: " << std::setprecision(4) << agent.epsilon << std::endl;
        }
    }

    auto end_time = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> duration = end_time - start_time;
    
    std::cout << "Training Complete. Time: " << duration.count() << "s, Speed: " 
              << episodes / duration.count() << " eps/s" << std::endl;
              
    return history_rewards;
}

// =============================================================================
// 5. TESTING & VISUALIZATION
// =============================================================================

std::vector<Point> test_agent(PerfectMaze& maze, DQNSolver& agent, Point start, Point end) {
    std::vector<Point> path;
    path.push_back(start);
    
    int cx = start.x;
    int cy = start.y;
    int tx = end.x;
    int ty = end.y;
    
    std::set<Point> visited;
    visited.insert(start);
    
    std::cout << "\nTesting Path: (" << start.x << "," << start.y << ") -> (" << end.x << "," << end.y << ")" << std::endl;
    
    int steps = 0;
    int max_steps = maze.width * maze.height * 2;
    
    // Disable exploration
    agent.epsilon = 0.0f; 

    while ((cx != tx || cy != ty) && steps < max_steps) {
        int action = agent.get_action(cx, cy, tx, ty);
        if (action == -1) break;
        
        int nx = cx + agent.dx[action];
        int ny = cy + agent.dy[action];
        
        Point np = {nx, ny};
        if (visited.count(np)) {
            std::cout << "Loop detected in test path!" << std::endl;
            // Break loop to prevent infinite cycling in testing
            break;
        }
        
        cx = nx;
        cy = ny;
        path.push_back({cx, cy});
        visited.insert({cx, cy});
        steps++;
    }
    
    if (cx == tx && cy == ty) {
        std::cout << "Target Reached in " << steps << " steps." << std::endl;
    } else {
        std::cout << "Failed to reach target." << std::endl;
    }
    
    return path;
}

int main() {
    // Configuration
    const int SIZE = 15;
    const double DENSITY = 0.15;
    const int EPISODES = 5000;
    
    // Initialize
    PerfectMaze maze(SIZE, SIZE, DENSITY);
    DQNSolver agent(maze, 0.95f, 1.0f);
    
    // Train
    train_agent(maze, agent, EPISODES);
    
    // Test
    Point start = {0, 0};
    Point end = {SIZE - 1, SIZE - 1};
    
    // Ensure start/end are valid (clearing obstacles)
    if (maze.grid[start.y][start.x] == 1) maze.grid[start.y][start.x] = 0;
    if (maze.grid[end.y][end.x] == 1) maze.grid[end.y][end.x] = 0;
    
    // Re-verify connectivity/actions after forcing start/end 
    // (In Python code this was just a direct set, simple fix)
    
    std::vector<Point> path = test_agent(maze, agent, start, end);
    save_ppm("result.ppm", SIZE, SIZE, maze.grid, path);
    
    return 0;
}
