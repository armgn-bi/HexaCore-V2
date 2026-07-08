#include <iostream>
#include <fstream>
#include <string>
#include <vector>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

int main() {
    std::string input_file = "result.ppm";
    std::string output_file = "result.png";
    
    std::ifstream ifs(input_file);
    if (!ifs) {
        std::cerr << "Error: Could not open " << input_file << " for reading.\n";
        return 1;
    }

    std::string p3;
    ifs >> p3;
    if (p3 != "P3") {
        std::cerr << "Error: Not a valid P3 PPM file (found: " << p3 << ").\n";
        return 1;
    }

    int width, height, max_color_val;
    ifs >> width >> height >> max_color_val;

    std::vector<unsigned char> pixels;
    pixels.reserve(width * height * 3);

    int r, g, b;
    for (int i = 0; i < width * height; ++i) {
        if (!(ifs >> r >> g >> b)) break;
        pixels.push_back(static_cast<unsigned char>(r));
        pixels.push_back(static_cast<unsigned char>(g));
        pixels.push_back(static_cast<unsigned char>(b));
    }

    ifs.close();

    // Write PNG
    if (stbi_write_png(output_file.c_str(), width, height, 3, pixels.data(), width * 3)) {
        std::cout << "Successfully converted " << input_file << " to " << output_file << "!\n";
    } else {
        std::cerr << "Error: Failed to write " << output_file << ".\n";
        return 1;
    }

    return 0;
}
