
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
// 2. OPTIMIZED SOLVER (Q-LEARNING)
// =============================================================================

class PerfectSolver {
public:
    PerfectMaze& maze;
    float lr;
    float gamma;
    float epsilon;
    float epsilon_min;
    float epsilon_decay;
    
    // q_table[y][x][action]
    std::vector<std::vector<std::vector<float>>> q_table;
    
    // dx/dy for actions 0, 1, 2, 3
    const int dx[4] = {1, 0, -1, 0};
    const int dy[4] = {0, 1, 0, -1};

    std::mt19937 rng;

    PerfectSolver(PerfectMaze& m, float learning_rate = 0.1, float discount_factor = 0.99, float exploration_rate = 1.0)
        : maze(m), lr(learning_rate), gamma(discount_factor), epsilon(exploration_rate) {
        
        epsilon_min = 0.01f;
        epsilon_decay = 0.995f;
        
        q_table.resize(maze.height, std::vector<std::vector<float>>(maze.width, std::vector<float>(4, 0.0f)));
        
        unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();
        rng.seed(seed);
    }

    int get_action(int x, int y, int tx, int ty) {
        const auto& possible_actions = maze.get_possible_actions(x, y);
        if (possible_actions.empty()) return -1;
        
        std::uniform_real_distribution<float> dist(0.0, 1.0);
        
        if (dist(rng) < epsilon) {
            std::uniform_int_distribution<int> action_dist(0, possible_actions.size() - 1);
            return possible_actions[action_dist(rng)];
        }
        
        float max_q = -1e9;
        std::vector<int> best_actions;
        
        for (int action : possible_actions) {
            float q = q_table[y][x][action];
            if (q > max_q) {
                max_q = q;
                best_actions.clear();
                best_actions.push_back(action);
            } else if (std::abs(q - max_q) < 1e-6) {
                best_actions.push_back(action);
            }
        }
        
        if (best_actions.empty()) return possible_actions[0]; // Fallback
        
        std::uniform_int_distribution<int> best_dist(0, best_actions.size() - 1);
        return best_actions[best_dist(rng)];
    }

    void update(int x, int y, int action, float reward, int nx, int ny, int tx, int ty) {
        float current_q = q_table[y][x][action];
        float max_next_q = 0.0f;
        
        const auto& next_actions = maze.get_possible_actions(nx, ny);
        if (!next_actions.empty()) {
            max_next_q = -1e9;
            for (int na : next_actions) {
                float q = q_table[ny][nx][na];
                if (q > max_next_q) max_next_q = q;
            }
        } else {
             // If no actions, q is 0 (or terminal)
             max_next_q = 0.0f;
        }
        
        // if max_next_q is still initial small value, set to 0
        if (max_next_q == -1e9) max_next_q = 0.0f;

        float new_q = current_q + lr * (reward + gamma * max_next_q - current_q);
        q_table[y][x][action] = new_q;
    }

    void decay_epsilon() {
        epsilon = std::max(epsilon_min, epsilon * epsilon_decay);
    }
};

// =============================================================================
// 3. HIGH-PERFORMANCE TRAINING LOOP
// =============================================================================

std::vector<float> train_agent(PerfectMaze& maze, PerfectSolver& agent, int episodes = 1000) {
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
        int max_steps = width * height;
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
            } else {
                reward = -1.0f;
                done = false;
            }
            
            agent.update(cx, cy, action, reward, nx, ny, tx, ty);
            
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
// 4. TESTING & VISUALIZATION
// =============================================================================

std::vector<Point> test_agent(PerfectMaze& maze, PerfectSolver& agent, Point start, Point end) {
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
    
    while ((cx != tx || cy != ty) && steps < max_steps) {
        const auto& possible_actions = maze.get_possible_actions(cx, cy);
        if (possible_actions.empty()) {
            std::cout << "Stuck!" << std::endl;
            break;
        }
        
        int best_action = -1;
        float max_q = -1e9;
        
        for (int action : possible_actions) {
            float q = agent.q_table[cy][cx][action];
            if (q > max_q) {
                max_q = q;
                best_action = action;
            }
        }
        
        if (best_action == -1) break;
        
        int nx = cx + agent.dx[best_action];
        int ny = cy + agent.dy[best_action];
        
        Point np = {nx, ny};
        if (visited.count(np)) {
            std::cout << "Loop detected in test path!" << std::endl;
            // Depending on strictness, we might break or continue.
            // Python code says 'pass', so loop continues.
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
    PerfectSolver agent(maze, 0.2f, 0.95f);
    
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
