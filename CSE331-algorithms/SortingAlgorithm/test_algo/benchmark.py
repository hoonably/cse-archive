import subprocess
import time
import os
from pathlib import Path
from collections import defaultdict
import csv

ALGORITHMS = {
    "merge_sort": "basic_sorting/merge_sort.cpp",  # ✅
    "heap_sort": "basic_sorting/heap_sort.cpp",  # ✅
    "bubble_sort": "basic_sorting/bubble_sort.cpp",  # ✅
    "insertion_sort": "basic_sorting/insertion_sort.cpp",  # ✅
    "selection_sort": "basic_sorting/selection_sort.cpp",  # ✅
    "quick_sort": "basic_sorting/quick_sort.cpp",  # ✅
    "quick_sort_random": "basic_sorting/quick_sort_random.cpp",  # ✅
    "library_sort": "advanced_sorting/library_sort.cpp",  # ✅
    "cocktail_shaker_sort": "advanced_sorting/cocktail_shaker_sort.cpp",  # ✅
    "tim_sort": "advanced_sorting/tim_sort.cpp",  # ✅
    "comb_sort": "advanced_sorting/comb_sort.cpp",  # ✅
    "tournament_sort": "advanced_sorting/tournament_sort.cpp",  # ✅
    "intro_sort": "advanced_sorting/intro_sort.cpp",  # ✅
}

INPUT_DIR = "../input"
MAIN_TEMPLATE = "main.cpp"
TEMP_MAIN = "temp_main.cpp"
TEMP_EXEC = "temp_exec"
REPEAT = 10

def run_once(exe_path, input_file):
    result = subprocess.run(
        [exe_path, input_file],
        capture_output=True,
        text=True
    )
    try:
        values = result.stdout.strip().split()
        if len(values) >= 2:
            elapsed = float(values[0])
            accuracy = float(values[1])
            return elapsed, accuracy
        else:
            return -1, 0.0
    except ValueError:
        return -1, 0.0


def compile_with_main(algo_name, algo_path):
    with open(MAIN_TEMPLATE, 'r') as f:
        code = f.read()
    code = code.replace("// #include PLACEHOLDER", f'#include "../{algo_path}"')  # include line
    code = code.replace("// run_sort(data);", f"{algo_name}(data);")  # function call

    with open(TEMP_MAIN, 'w') as f:
        f.write(code)

    result = subprocess.run(["g++", "-O2", "-std=c++17", "-o", TEMP_EXEC, TEMP_MAIN])
    return result.returncode == 0

def warmup_io(input_path):
    subprocess.run([f"./{TEMP_EXEC}", input_path],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def save_results_to_csv(results, algo_name):
    csv_path = f"results/csv/{algo_name}.csv"
    with open(csv_path, "w", newline="") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["algo_name", "input_file", "time_sec", "accuracy"])
        for input_file, (time_sec, accuracy) in results.items():
            writer.writerow([
                algo_name,
                input_file,
                f"{time_sec:.7f}",
                f"{accuracy:.4f}"
            ])
    print(f"📄 Results for {algo_name} saved to {csv_path}")

def benchmark_all():
    input_files = sorted(f for f in os.listdir(INPUT_DIR) if f.endswith(".txt"))

    for algo_name, algo_cpp in ALGORITHMS.items():
        print(f"\n[+] Benchmarking {algo_name}")
        results = {}

        if not compile_with_main(algo_name, algo_cpp):
            print(f"    ❌ Compile failed for {algo_name}")
            continue

        for input_file in input_files:
            input_path = os.path.join(INPUT_DIR, input_file)

            time_list = []
            acc_list = []

            # Warmup
            warmup_io(input_path)

            is_stack_overflow = False
            rep = 0
            while rep < REPEAT:
                rep += 1
                elapsed, accuracy = run_once(f"./{TEMP_EXEC}", input_path)

                if elapsed == -1:
                    is_stack_overflow = True
                    break

                time_list.append(elapsed)
                acc_list.append(accuracy)

                # If you dont want to run over 24 hours
                # if elapsed > 300:
                #     print(f"    {input_file}: 🕖 Time is over 5 minute, stop repeat")
                #     break

            if is_stack_overflow:
                print(f"    {input_file:<25}: ❌ Stack Overflow")
                results[input_file] = (-1, -1)
            else:
                median_time = round(sum(time_list) / rep, 7)
                avg_accuracy = round(sum(acc_list) * 100 / rep, 4)
                print(f"    {input_file:<25}: {median_time:.7f} sec, Accuracy: {avg_accuracy:.4f}%")
                results[input_file] = (median_time, avg_accuracy)

        # Save to CSV
        save_results_to_csv(results, algo_name)


if __name__ == "__main__":
    
    results = benchmark_all()

    if os.path.exists(TEMP_MAIN):
        os.remove(TEMP_MAIN)
    if os.path.exists(TEMP_EXEC):
        os.remove(TEMP_EXEC)