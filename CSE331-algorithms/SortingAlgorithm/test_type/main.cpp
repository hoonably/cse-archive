// main_template_typed.cpp

#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <chrono>
#include <iomanip>
#include <cmath>

// #include PLACEHOLDER

template <typename T>
std::vector<T> read_input(const std::string& filename) {
    std::vector<T> data;
    std::ifstream infile(filename);
    T num;
    while (infile >> num) data.push_back(num);
    return data;
}

template <typename T>
double calculate_accuracy(const std::vector<T>& data) {
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
    std::string type = argv[1];
    std::string input_path = argv[2];

    double time = 0.0, accuracy = 0.0;

    if (type == "int") {
        std::vector<int> data = read_input<int>(input_path);
        auto start = std::chrono::high_resolution_clock::now();
        // run_sort(data);
        auto end = std::chrono::high_resolution_clock::now();
        time = std::chrono::duration<double>(end - start).count();
        accuracy = calculate_accuracy(data);
    }
    else if (type == "long long") {
        std::vector<long long> data = read_input<long long>(input_path);
        auto start = std::chrono::high_resolution_clock::now();
        // run_sort(data);
        auto end = std::chrono::high_resolution_clock::now();
        time = std::chrono::duration<double>(end - start).count();
        accuracy = calculate_accuracy(data);
    }
    else if (type == "float") {
        std::vector<float> data = read_input<float>(input_path);
        auto start = std::chrono::high_resolution_clock::now();
        // run_sort(data);
        auto end = std::chrono::high_resolution_clock::now();
        time = std::chrono::duration<double>(end - start).count();
        accuracy = calculate_accuracy(data);
    }
    else if (type == "double") {
        std::vector<double> data = read_input<double>(input_path);
        auto start = std::chrono::high_resolution_clock::now();
        // run_sort(data);
        auto end = std::chrono::high_resolution_clock::now();
        time = std::chrono::duration<double>(end - start).count();
        accuracy = calculate_accuracy(data);
    }

    std::cout << time << " " << accuracy << std::endl;
    return 0;
}
