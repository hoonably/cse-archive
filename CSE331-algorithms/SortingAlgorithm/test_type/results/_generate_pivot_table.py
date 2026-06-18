import csv
from collections import defaultdict

INPUT_FILE = "__combined_results.csv"
OUTPUT_FILE = "__pivot_table.csv"

DESIRED_TYPES = ["int", "long long", "float", "double"]
DESIRED_ALGOS = [
    "merge_sort",
    "heap_sort",
    "bubble_sort",
    "insertion_sort",
    "selection_sort",
    "quick_sort",
    "quick_sort_random",
    "library_sort",
    "cocktail_shaker_sort",
    "tim_sort",
    "comb_sort",
    "tournament_sort",
    "intro_sort"
]

def generate_pivot_table():
    data = defaultdict(dict)

    with open(INPUT_FILE, newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            algo = row["algorithm"]
            typ = row["type"]
            time = float(row["time_sec"])
            data[algo][typ] = f"{time:.6f}"

    with open(OUTPUT_FILE, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["algorithm"] + DESIRED_TYPES)

        for algo in DESIRED_ALGOS:
            row = [algo]
            for typ in DESIRED_TYPES:
                row.append(data[algo].get(typ, ""))
            writer.writerow(row)

    print(f"✅ Pivot table saved to: {OUTPUT_FILE}")

if __name__ == "__main__":
    generate_pivot_table()
