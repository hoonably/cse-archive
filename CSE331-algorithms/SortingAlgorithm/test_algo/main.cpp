#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <chrono>
#include <iomanip>
#include <cmath>
// #include PLACEHOLDER

std::vector<int> read_input(const std::string& filename) {
    std::vector<int> data;
    std::ifstream infile(filename);
    int num;
    while (infile >> num) data.push_back(num);
    return data;
}

void write_output(const std::string& filename, const std::vector<int>& data) {
    std::ofstream outfile(filename);
    for (int num : data) outfile << num << " ";
    outfile << "\n";
}

double calculate_accuracy(const std::vector<int>& data) {
    if (data.size() <= 1) {
        return 1.0;
    }
    
    int violations = 0;
    for (size_t i = 0; i < data.size() - 1; ++i) {
        if (data[i] > data[i + 1]) {
            violations++;
        }
    }
    
    double score = 1.0 - (static_cast<double>(violations) / (data.size() - 1));
    return round(score * 10000) / 10000.0;
}

int main(int argc, char* argv[]) {
    std::vector<int> data = read_input(argv[1]);
    
    auto start = std::chrono::high_resolution_clock::now();
    // run_sort(data);  // This will be {algo_name}(data);
    auto end = std::chrono::high_resolution_clock::now();

    std::chrono::duration<double> elapsed = end - start;
    
    // Calculate accuracy
    double accuracy = calculate_accuracy(data);
    
    // Output elapsed time and accuracy
    std::cout << elapsed.count() << " " << accuracy << std::endl;

    write_output(argv[2], data);
    return 0;
}