#ifndef MAZE_H
#define MAZE_H

#define MAX_SIZE 20
#define NUM_ACTIONS 4

// Donanım Fonksiyon Prototipi
void q_learning_accel(int width, int height, int target_episodes, 
                      int grid[MAX_SIZE][MAX_SIZE], 
                      float q_table[MAX_SIZE][MAX_SIZE][NUM_ACTIONS]);

#endif