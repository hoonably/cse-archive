# Make graphs from CSV files — Save both PDF and PNG

import os
import csv
import re
import matplotlib.pyplot as plt

plt.rc('font', size=14)          # 기본 글자 크기 (ticks, labels 등)
plt.rc('axes', titlesize=16)     # 제목(title) 크기
plt.rc('axes', labelsize=14)     # x/y축 라벨 크기
plt.rc('xtick', labelsize=12)    # x축 눈금 글씨
plt.rc('ytick', labelsize=12)    # y축 눈금 글씨
plt.rc('legend', fontsize=12)    # 범례 글씨 크기
plt.rc('figure', titlesize=16)   # 전체 figure 제목 (있다면)

CATEGORIES = ["sorted_asc", "sorted_desc", "random", "partial_50", "partial_80"]
CSV_DIR = "csv"
GRAPH_DIR = "graph"

os.makedirs(GRAPH_DIR, exist_ok=True)

def load_csv(filepath):
    data = {cat: [] for cat in CATEGORIES}
    with open(filepath, newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            fname = row["input_file"]
            try:
                time = float(row["time_sec"])
            except ValueError:
                continue

            match = re.match(r"n0*([0-9]+)_(.+)\.txt", fname)
            if not match:
                continue
            n = int(match.group(1))
            kind = match.group(2)
            if kind in data:
                data[kind].append((n, time))
    return data

def plot_one_algorithm(csv_path):
    algo_name = os.path.splitext(os.path.basename(csv_path))[0]
    print(f"📊 Plotting {algo_name}...")

    series = load_csv(csv_path)

    plt.figure(figsize=(10, 6))
    for kind, points in series.items():
        if not points:
            continue
        points.sort()
        x = [n for n, _ in points]
        y = [t for _, t in points]
        plt.plot(x, y, marker='o', label=kind)

    plt.xlabel("Input Size (n)")
    plt.ylabel("Execution Time (sec)")
    plt.title(f"Execution Time by Input Type: {algo_name}")
    plt.xscale("log")
    plt.yscale("log")
    plt.grid(True, which="both", linestyle="--")
    plt.legend()
    plt.tight_layout()

    # 저장: PDF (벡터) + PNG (비트맵)
    plt.savefig(os.path.join(GRAPH_DIR, f"{algo_name}.pdf"), bbox_inches="tight")
    plt.savefig(os.path.join(GRAPH_DIR, f"{algo_name}.png"), dpi=300, bbox_inches="tight")
    plt.close()

def plot_all():
    for filename in os.listdir(CSV_DIR):
        if filename.endswith(".csv") and filename != "__combined_results.csv":
            plot_one_algorithm(os.path.join(CSV_DIR, filename))

if __name__ == "__main__":
    plot_all()
