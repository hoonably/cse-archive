import os
import subprocess
import csv

# 설정
ALGORITHMS = {
    "merge_sort": "basic_sorting/merge_sort.cpp",
    "heap_sort": "basic_sorting/heap_sort.cpp",
    "bubble_sort": "basic_sorting/bubble_sort.cpp",
    "insertion_sort": "basic_sorting/insertion_sort.cpp",
    "selection_sort": "basic_sorting/selection_sort.cpp",
    "quick_sort": "basic_sorting/quick_sort.cpp",
    "quick_sort_random": "basic_sorting/quick_sort_random.cpp",
    "library_sort": "advanced_sorting/library_sort.cpp",
    "cocktail_shaker_sort": "advanced_sorting/cocktail_shaker_sort.cpp",
    "tim_sort": "advanced_sorting/tim_sort.cpp",
    "comb_sort": "advanced_sorting/comb_sort.cpp",
    "tournament_sort": "advanced_sorting/tournament_sort.cpp",
    "intro_sort": "advanced_sorting/intro_sort.cpp",
}

TYPES = ["int", "long long", "float", "double"]
INPUT_FILE = "../input/n1000000_random.txt"
MAIN_TEMPLATE = "main.cpp"
TEMP_MAIN = "temp_typed.cpp"
TEMP_EXEC = "temp_exec"
REPEAT = 10

RESULTS_DIR = "results"
os.makedirs(RESULTS_DIR, exist_ok=True)

def compile_main_template(algo_name, algo_path):
    with open(MAIN_TEMPLATE, 'r') as f:
        code = f.read()
    code = code.replace("// #include PLACEHOLDER", f'#include "../{algo_path}"')
    code = code.replace("// run_sort(data);", f"{algo_name}(data);")
    with open(TEMP_MAIN, 'w') as f:
        f.write(code)
    return subprocess.run(["g++", "-O2", "-std=c++17", "-o", TEMP_EXEC, TEMP_MAIN]).returncode == 0

def run_n_times(type_name, n=REPEAT):
    times, accs = [], []

    rep = 0
    while rep < REPEAT:
        rep += 1
        result = subprocess.run(
            [f"./{TEMP_EXEC}", type_name, INPUT_FILE],
            capture_output=True, text=True
        )
        try:
            time_str, acc_str = result.stdout.strip().split()
            time = float(time_str)
            times.append(time)
            accs.append(float(acc_str))
        except:
            times.append(-1.0)
            accs.append(0.0)

        # If you dont want to run over 24 hours
        # if time > 300:
        #     print(f"    🕖 Time is over 5 minute, stop repeat")
        #     break

    avg_time = round(sum(times) / rep, 7)
    avg_acc = round(sum(accs) / rep, 4)
    return avg_time, avg_acc

def benchmark_all():
    for algo_name, algo_path in ALGORITHMS.items():
        print(f"\n[+] Benchmarking {algo_name}")
        if not compile_main_template(algo_name, algo_path):
            print("    ❌ Compile failed")
            continue

        rows = []
        for typ in TYPES:
            time_sec, acc = run_n_times(typ)
            print(f"    {typ:<10}: {time_sec:.7f} sec, Accuracy: {acc:.4f}")
            rows.append([algo_name, typ, time_sec, acc])

        csv_path = os.path.join(RESULTS_DIR, f"{algo_name}.csv")
        with open(csv_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["algorithm", "type", "time_sec", "accuracy"])
            writer.writerows(rows)

        print(f"    📄 Saved to {csv_path}")

    if os.path.exists(TEMP_MAIN): os.remove(TEMP_MAIN)
    if os.path.exists(TEMP_EXEC): os.remove(TEMP_EXEC)

benchmark_all()
