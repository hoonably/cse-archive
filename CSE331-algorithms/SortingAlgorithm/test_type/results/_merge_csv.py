# merge_all_csv_files.py

import csv
import os

OUTPUT_FILE = "__combined_results.csv"

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

def merge_all_csv_files():
    merged_rows = []
    header = None

    for filename in sorted(os.listdir()):
        if not filename.endswith(".csv") or filename in {OUTPUT_FILE, "__pivot_table.csv"}:
            continue

        with open(filename, newline='') as infile:
            reader = csv.reader(infile)
            file_header = next(reader)

            if header is None:
                header = file_header  # 저장할 헤더는 첫 파일에서 추출

            for row in reader:
                merged_rows.append(row)

    # 정렬 기준: 알고리즘 순서 > 타입 순서
    algo_idx = header.index("algorithm")
    type_idx = header.index("type")

    def sort_key(row):
        algo = row[algo_idx]
        typ = row[type_idx]
        return (
            DESIRED_ALGOS.index(algo) if algo in DESIRED_ALGOS else float('inf'),
            DESIRED_TYPES.index(typ) if typ in DESIRED_TYPES else float('inf')
        )

    merged_rows.sort(key=sort_key)

    with open(OUTPUT_FILE, "w", newline="") as outfile:
        writer = csv.writer(outfile)
        writer.writerow(header)
        writer.writerows(merged_rows)

    print(f"✅ Merged and sorted into: {OUTPUT_FILE}")

if __name__ == "__main__":
    merge_all_csv_files()
