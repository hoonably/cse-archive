#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <limits>
// #include PLACEHOLDER

struct StableItem {
    int value;
    int index;

    // Primary: compare by value only
    bool operator<(const StableItem& other) const {
        return value < other.value;
    }

    bool operator>(const StableItem& other) const {
        return value > other.value;
    }

    bool operator<=(const StableItem& other) const {
        return value <= other.value;
    }

    bool operator>=(const StableItem& other) const {
        return value >= other.value;
    }

    bool operator==(const StableItem& other) const {
        return value == other.value;
    }

    bool operator!=(const StableItem& other) const {
        return value != other.value;
    }
};

std::vector<StableItem> read_input(const std::string& filename) {
    std::vector<StableItem> data;
    std::ifstream infile(filename);
    int value, index;
    while (infile >> value >> index) {
        data.push_back({value, index});
    }
    return data;
}

void write_output(const std::string& filename, const std::vector<StableItem>& data) {
    std::ofstream outfile(filename);
    for (const auto& item : data) {
        outfile << item.value << " " << item.index << "\n";
    }
}

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: ./exec input.txt output.txt\n";
        return 1;
    }

    std::string input_path = argv[1];
    std::string output_path = argv[2];

    std::vector<StableItem> data = read_input(input_path);

    // run_sort(data);  // 자동 삽입됨 (ex: intro_sort(data);)

    write_output(output_path, data);
    return 0;
}
