import subprocess
import os
import csv

INPUT_FILE = "input/stability_1000.txt"
OUTPUT_DIR = "output"
REPEAT = 10

ALGORITHMS = {
    "merge_sort": "basic_sorting/merge_sort.cpp",  # ✅ (Stable)
    "heap_sort": "basic_sorting/heap_sort.cpp",  # ❌
    "bubble_sort": "basic_sorting/bubble_sort.cpp",  # ✅ (Stable)
    "insertion_sort": "basic_sorting/insertion_sort.cpp",  # ✅ (Stable)
    "selection_sort": "basic_sorting/selection_sort.cpp",  # ❌
    "quick_sort": "basic_sorting/quick_sort.cpp",  # ❌
    "library_sort": "advanced_sorting/library_sort.cpp",  # ❌
    "cocktail_shaker_sort": "advanced_sorting/cocktail_shaker_sort.cpp",  # ✅ (Stable)
    "tim_sort": "advanced_sorting/tim_sort.cpp",  # ✅ (Stable)
    "comb_sort": "advanced_sorting/comb_sort.cpp",  # ❌
    "tournament_sort": "advanced_sorting/tournament_sort.cpp",  # ✅ (Stable)
    "intro_sort": "advanced_sorting/intro_sort.cpp",  # ❌
}

MAIN_TEMPLATE = "main.cpp"
TEMP_MAIN = "temp.cpp"
TEMP_EXEC = "temp_exec"
TEMP_ALGO = "temp_algo.cpp"

def read_struct_input(filepath):
    data = []
    with open(filepath) as f:
        for line in f:
            v, idx = map(int, line.strip().split())
            data.append((v, idx))
    return data

def is_stable(original, sorted_data):
    from collections import defaultdict

    group_original = defaultdict(list)
    group_sorted = defaultdict(list)

    for v, i in original:
        group_original[v].append(i)
    for v, i in sorted_data:
        group_sorted[v].append(i)

    for v in group_original:
        if group_original[v] != group_sorted[v]:
            return False
    return True

def compile_with_main(algo_name, algo_path):
    # 1. make temp_main
    with open(MAIN_TEMPLATE) as f:
        code = f.read()
    code = code.replace("// #include PLACEHOLDER", f'#include "temp_algo.cpp"')
    code = code.replace("// run_sort(data);", f"{algo_name}(data);")

    with open(TEMP_MAIN, "w") as f:
        f.write(code)

    # 2. Change sentinel for StableItem
    algo_full_path = os.path.join("..", algo_path)
    with open(algo_full_path) as f:
        algo_code = f.read()
    algo_code = algo_code.replace("std::numeric_limits<T>::max()", "{std::numeric_limits<int>::max(), -1}")

    with open(TEMP_ALGO, "w") as f:
        f.write(algo_code)

    # 3. Compile
    result = subprocess.run(["g++", "-O2", "-std=c++17", "-o", TEMP_EXEC, TEMP_MAIN])
    return result.returncode == 0


def benchmark_stability():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    original_data = read_struct_input(INPUT_FILE)

    results = []

    for algo_name, algo_cpp in ALGORITHMS.items():
        print(f"\n[+] Checking stability: {algo_name}")
        if not compile_with_main(algo_name, algo_cpp):
            print(f"    ❌ Compile failed for {algo_name}")
            continue

        output_file = f"{OUTPUT_DIR}/{algo_name}.txt"
        is_stable_all = True

        for _ in range(REPEAT):
            subprocess.run([f"./{TEMP_EXEC}", INPUT_FILE, output_file],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            sorted_data = read_struct_input(output_file)
            if not is_stable(original_data, sorted_data):
                is_stable_all = False
                break

        result = "Stable" if is_stable_all else "Unstable"
        print(f"    {'✅' if is_stable_all else '❌'} {result}")
        results.append((algo_name, result))

    # 🔁 overwrite
    with open("stability.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["algorithm", "stability"])
        writer.writerows(results)

    if os.path.exists(TEMP_MAIN): os.remove(TEMP_MAIN)
    if os.path.exists(TEMP_EXEC): os.remove(TEMP_EXEC)
    if os.path.exists(TEMP_ALGO): os.remove(TEMP_ALGO)


if __name__ == "__main__":
    benchmark_stability()
