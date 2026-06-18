#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <thread>
#include <atomic>
#include <chrono>
#include <mach/mach.h>

// #include PLACEHOLDER

std::atomic<bool> keep_running(true);

double get_current_memory_kb() {
    task_basic_info_data_t info;
    mach_msg_type_number_t size = TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size) != KERN_SUCCESS)
        return -1;
    return info.resident_size / 1024.0;
}

void monitor_memory_usage(std::atomic<int>& phase_flag, double& sorting_peak) {
    int prev_phase = -1;
    sorting_peak = 0.0;

    while (keep_running.load()) {
        double mem = get_current_memory_kb();
        int current_phase = phase_flag.load();

        if (current_phase == 1 && mem > sorting_peak) {
            sorting_peak = mem;  // 정렬 중 peak 메모리 추적
        }

        if (current_phase != prev_phase) {
            if (current_phase == 0) std::cout << "# MAKING VECTOR\n";
            else if (current_phase == 1) std::cout << "# SORTING\n";
            prev_phase = current_phase;
        }

        std::cout << mem << "\n";
        std::this_thread::sleep_for(std::chrono::microseconds(10));
    }
}

template <typename T>
std::vector<T> read_input(const std::string& filename) {
    std::vector<T> data;
    std::ifstream infile(filename);
    T num;
    while (infile >> num) data.push_back(num);
    return data;
}

int main() {
    std::atomic<int> phase_flag(-1);
    double sorting_peak = 0.0;

    std::thread monitor(monitor_memory_usage, std::ref(phase_flag), std::ref(sorting_peak));

    double mem_before_vector = get_current_memory_kb();
    std::cout << "# MEM_BEFORE_VECTOR " << mem_before_vector << "\n";

    phase_flag = 0;
    std::vector<int> data = read_input<int>("../input/n0100000_random.txt");

    double mem_after_vector = get_current_memory_kb();
    std::cout << "# MEM_AFTER_VECTOR " << mem_after_vector << "\n";

    phase_flag = 1;
    // run_sort(data);

    phase_flag = 2;
    keep_running = false;
    monitor.join();

    std::cout << "# MEM_SORTING_PEAK " << sorting_peak << "\n";

    return 0;
}
