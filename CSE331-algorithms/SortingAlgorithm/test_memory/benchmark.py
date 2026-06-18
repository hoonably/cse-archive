import subprocess
import csv
import matplotlib.pyplot as plt
import numpy as np
import os

ALGORITHMS = {
    "merge_sort": "basic_sorting/merge_sort.cpp",
    "heap_sort": "basic_sorting/heap_sort.cpp",
    "bubble_sort": "basic_sorting/bubble_sort.cpp",
    "insertion_sort": "basic_sorting/insertion_sort.cpp",
    "selection_sort": "basic_sorting/selection_sort.cpp",
    "quick_sort": "basic_sorting/quick_sort.cpp",
    # "quick_sort_random": "basic_sorting/quick_sort_random.cpp",
    "library_sort": "advanced_sorting/library_sort.cpp",
    "tim_sort": "advanced_sorting/tim_sort.cpp",
    "cocktail_shaker_sort": "advanced_sorting/cocktail_shaker_sort.cpp",
    "comb_sort": "advanced_sorting/comb_sort.cpp",
    "tournament_sort": "advanced_sorting/tournament_sort.cpp",
    "intro_sort": "advanced_sorting/intro_sort.cpp",
}

MAIN_TEMPLATE = "main.cpp"
TEMP_MAIN = "temp_main.cpp"
TEMP_EXEC = "temp_exec"

def compile_with_main(algo_name, algo_path):
    with open(MAIN_TEMPLATE, 'r') as f:
        code = f.read()
    code = code.replace("// #include PLACEHOLDER", f'#include "../{algo_path}"')
    code = code.replace("// run_sort(data);", f"{algo_name}(data);")
    with open(TEMP_MAIN, 'w') as f:
        f.write(code)
    result = subprocess.run(["g++", "-O2", "-std=c++17", "-o", TEMP_EXEC, TEMP_MAIN])
    return result.returncode == 0

def parse_memory_values_from_stdout(stdout):
    mem = {
        "before_vector": None,
        "after_vector": None,
        "sorting_peak": None
    }
    mem_usage = []
    phases = []
    current_phase = "UNKNOWN"
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("#"):
            if "MAKING VECTOR" in line:
                current_phase = "MAKING VECTOR"
            if "SORTING" in line:
                current_phase = "SORTING"
            if "MEM_BEFORE_VECTOR" in line:
                mem["before_vector"] = float(line.split()[-1])
            if "MEM_AFTER_VECTOR" in line:
                mem["after_vector"] = float(line.split()[-1])
            if "MEM_SORTING_PEAK" in line:
                mem["sorting_peak"] = float(line.split()[-1])
            continue
        try:
            mem_usage.append(float(line))
            phases.append(current_phase)
        except ValueError:
            continue
    return mem, mem_usage, phases

def plot_memory_log(algorithm_name, mem_usage, phases):
    if not mem_usage:
        return
    phase_colors = {
        "MAKING VECTOR": "blue",
        "SORTING": "red",
        "UNKNOWN": "gray"
    }
    x_vals = np.arange(len(mem_usage)) * 0.01  # 10μs → ms

    plt.figure(figsize=(10, 4))
    start = 0
    while start < len(mem_usage):
        current = phases[start]
        end = start
        while end < len(mem_usage) and phases[end] == current:
            end += 1
        plt.plot(x_vals[start:end], mem_usage[start:end],
                 color=phase_colors.get(current, "black"), linewidth=1.4)
        start = end

    plt.title(f"Memory Usage with Phases - {algorithm_name}")
    plt.xlabel("Time (ms)")
    plt.ylabel("Memory (KB)")
    plt.grid(True)
    plt.tight_layout()
    
    plot_dir = "memory_graph"
    os.makedirs(plot_dir, exist_ok=True)

    png_file = f"{plot_dir}/{algorithm_name}.png"
    pdf_file = f"{plot_dir}/{algorithm_name}.pdf"

    plt.savefig(png_file)
    plt.savefig(pdf_file)
    plt.close()

    print(f"    📈 Saved graph to {png_file} and {pdf_file}")


def run_and_collect(algo_name, repeat=10):
    print(f"[+] Benchmarking {algo_name} x {repeat}")
    before_list, after_list, peak_list = [], [], []

    for i in range(repeat):
        result = subprocess.run(["./temp_exec"], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"    ❌ Runtime error on iteration {i+1}")
            return None

        mem_stats, mem_usage, phases = parse_memory_values_from_stdout(result.stdout)

        # Only plot the last iteration
        if i == repeat - 1:
            plot_memory_log(algo_name, mem_usage, phases)

        before = mem_stats["before_vector"]
        after = mem_stats["after_vector"]
        peak = mem_stats["sorting_peak"]

        if None in (before, after, peak):
            print(f"    ⚠️ Incomplete data on iteration {i+1}")
            return None

        before_list.append(before)
        after_list.append(after)
        peak_list.append(peak)

    avg_before = round(sum(before_list) / repeat, 2)
    avg_after = round(sum(after_list) / repeat, 2)
    avg_peak = round(sum(peak_list) / repeat, 2)
    vector_only = round(avg_after - avg_before, 2)
    sort_overhead = round(avg_peak - avg_after, 2)

    return [algo_name, avg_before, avg_after, avg_peak, vector_only, sort_overhead]



def save_memory_csv(data, filename="memory_stats.csv"):
    with open(filename, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "algorithm",
            "before_vector",
            "after_vector",
            "sorting_peak",
            "vector_only",
            "sort_overhead"
        ])
        writer.writerows(data)
    print(f"📄 Saved memory stats to {filename}")


def full_benchmark():
    results = []
    for algo_name, algo_path in ALGORITHMS.items():
        if not compile_with_main(algo_name, algo_path):
            print(f"    ❌ Compile failed for {algo_name}")
            continue
        row = run_and_collect(algo_name)
        if row:
            results.append(row)

    if os.path.exists(TEMP_MAIN): os.remove(TEMP_MAIN)
    if os.path.exists(TEMP_EXEC): os.remove(TEMP_EXEC)

    save_memory_csv(results)

full_benchmark()
