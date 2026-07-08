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
#include "maze.h"
#include "Qlearning_2.cpp"



class PerfectMaze {
public:
    int width;
    int height;
    std::vector<std::vector<int>> grid;
    Point start_pos;
    Point end_pos;

    PerfectMaze(int w = 15, int h = 15, double obstacle_density = 0.1) 
        : width(w), height(h) {
        grid.resize(height, std::vector<int>(width, 0));
        start_pos = {0, 0};
        end_pos = {width - 1, height - 1};
        
        generate_perfect_maze(obstacle_density);
    }

    bool is_valid(int x, int y) const {
        return x >= 0 && x < width && y >= 0 && y < height && grid[y][x] == 0;
    }
    
    // Helper to get valid actions for host-side testing
    std::vector<int> get_possible_actions(int x, int y) const {
         std::vector<int> actions;
         if (x + 1 < width && grid[y][x + 1] == 0) actions.push_back(0); // Right
         if (y + 1 < height && grid[y + 1][x] == 0) actions.push_back(1); // Down
         if (x - 1 >= 0 && grid[y][x - 1] == 0) actions.push_back(2); // Left
         if (y - 1 >= 0 && grid[y - 1][x] == 0) actions.push_back(3); // Up
         return actions;
    }

private:
    void generate_perfect_maze(double density) {
        // Clear grid
        for(auto& row : grid) std::fill(row.begin(), row.end(), 0);

        int n_obstacles = static_cast<int>(width * height * density);
        std::vector<int> indices(width * height);
        for(int i=0; i < width * height; ++i) indices[i] = i;

        unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();
        std::mt19937 g(seed);
        std::shuffle(indices.begin(), indices.end(), g);

        int count = 0;
        for (int idx : indices) {
            if (count >= n_obstacles) break;
            int y = idx / width;
            int x = idx % width;
            if ((x == start_pos.x && y == start_pos.y) || (x == end_pos.x && y == end_pos.y)) continue;
            grid[y][x] = 1;
            count++;
        }
        ensure_connectivity();
    }

    void ensure_connectivity() {
        // Simplified connectivity check for brevity/host-side
        // Ideally reuse BFS from previous version
         // ... (Preserving BFS logic roughly or just trust RNG for demo) ...
         // For reliability, let's just clear a path directly if it's blocked, 
         // OR, rely on the original BFS logic. I will re-implement a simple BFS here 
         // to keep the file self-contained and correct.
         
         while(true) {
             std::vector<std::vector<bool>> visited(height, std::vector<bool>(width, false));
             std::deque<Point> queue;
             queue.push_back(start_pos);
             visited[start_pos.y][start_pos.x] = true;
             
             int reachable = 0;
             int dx[] = {0, 1, 0, -1};
             int dy[] = {1, 0, -1, 0};
             
             while(!queue.empty()){
                 Point p = queue.front(); queue.pop_front();
                 reachable++;
                 for(int i=0; i<4; ++i) {
                     int nx = p.x + dx[i];
                     int ny = p.y + dy[i];
                     if(nx >=0 && nx < width && ny >=0 && ny < height && grid[ny][nx] == 0 && !visited[ny][nx]) {
                         visited[ny][nx] = true;
                         queue.push_back({nx, ny});
                     }
                 }
             }
             
             // Check if end is reachable
             if (visited[end_pos.y][end_pos.x]) break;
             
             // If not, clear some random obstacles
             bool changed = false;
             for(int i=0; i<10; ++i) {
                  int rx = rand() % width;
                  int ry = rand() % height;
                  if (grid[ry][rx] == 1) {
                      grid[ry][rx] = 0;
                      changed = true;
                  }
             }
             if(!changed) break; // Should eventually work
         }
    }
};

// =============================================================================
// 2. HOST MAIN
// =============================================================================
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

int main() {
    // Configuration
    const int SIZE = 15;
    const double DENSITY = 0.15;
    const int EPISODES = 5000;
    
    // 1. Initialize Host Maze
    PerfectMaze maze(SIZE, SIZE, DENSITY);
    
    // 2. Prepare Data for Hardware
    int hw_grid[MAX_SIZE][MAX_SIZE];
    float hw_q_table[MAX_SIZE][MAX_SIZE][NUM_ACTIONS];
    
    // Copy Maze to Fixed Array
    for(int y=0; y<MAX_SIZE; ++y) {
        for(int x=0; x<MAX_SIZE; ++x) {
            if (y < maze.height && x < maze.width) {
                 hw_grid[y][x] = maze.grid[y][x];
            } else {
                 hw_grid[y][x] = 1; // Pad with obstacles
            }
            for(int k=0; k<NUM_ACTIONS; ++k) {
                hw_q_table[y][x][k] = 0.0f;
            }
        }
    }
    
    // 3. Run Hardware Acceleration (Simulation)
    std::cout << "Starting Hardware Simulation..." << std::endl;
    auto start_time = std::chrono::high_resolution_clock::now();
    
    q_learning_accel(SIZE, SIZE, EPISODES, hw_grid, hw_q_table);
    
    auto end_time = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> duration = end_time - start_time;
    std::cout << "Hardware Logic Complete. Time: " << duration.count() << "s" << std::endl;

    // 4. Test Result (Host Side)
    Point start = {0, 0};
    Point end = {SIZE - 1, SIZE - 1};
    std::vector<Point> path;
    path.push_back(start);
    int cx = start.x, cy = start.y;
    int steps = 0;
    
    std::cout << "Testing Learned Policy..." << std::endl;
    
    while((cx != end.x || cy != end.y) && steps < SIZE*SIZE*2) {
        float max_q = -1e9;
        int best_a = -1;
        
        // Read from result q_table
        auto actions = maze.get_possible_actions(cx, cy);
        for(int action : actions) {
             if (hw_q_table[cy][cx][action] > max_q) {
                 max_q = hw_q_table[cy][cx][action];
                 best_a = action;
             }
        }
        
        if (best_a == -1) break;
        
        int dx[] = {1, 0, -1, 0};
        int dy[] = {0, 1, 0, -1};
        
        cx += dx[best_a];
        cy += dy[best_a];
        path.push_back({cx, cy});
        steps++;
    }
    
    if (cx == end.x && cy == end.y) {
        std::cout << "Success! Reached target in " << steps << " steps." << std::endl;
    } else {
        std::cout << "Failed to reach target." << std::endl;
    }

    save_ppm("result.ppm", SIZE, SIZE, maze.grid, path);
    return 0;
}
