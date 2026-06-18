import os
import re
import pandas as pd
from tabulate import tabulate

tour_root = "tour_paths"
output_dir = "summary"
os.makedirs(output_dir, exist_ok=True)

all_data = []

# === STEP 1: .tour 파일 읽기 ===
for dataset_dir in os.listdir(tour_root):
    dataset_path = os.path.join(tour_root, dataset_dir)
    if not os.path.isdir(dataset_path):
        continue

    for filename in os.listdir(dataset_path):
        if not filename.endswith(".tour"):
            continue

        tour_path = os.path.join(dataset_path, filename)

        dataset = algo = None
        length = time = None
        dimension = None
        opt_iters = 0  # default

        with open(tour_path) as f:
            for line in f:
                line = line.strip()
                if line.startswith("NAME"):
                    dataset = line.split(":", 1)[-1].strip()
                    dataset = dataset.replace(".tsp", "").replace(".tour", "").replace(".txt", "").replace("./TSPLIB/", "")
                elif line.startswith("DIMENSION"):
                    try:
                        dimension = int(line.split(":", 1)[-1].strip())
                    except:
                        pass
                elif line.startswith("COMMENT"):
                    content = line.split(":", 1)[-1].strip()
                    if content.strip().upper() == "OPT":
                        algo = "OPT"
                    elif "Algorithm" in content:
                        algo = content.replace("Algorithm", "").strip()
                    elif "2-opt iterations" in content:
                        m = re.search(r"2-opt iterations\s+(\d+)", content)
                        if m:
                            opt_iters = int(m.group(1))

                    elif "Length" in content or "length" in content or "Tour length" in content:
                        m = re.search(r"(\d+(?:\.\d+)?)", content)
                        if m:
                            length = float(m.group(1))
                    elif "Elapsed time" in content:
                        m = re.search(r"\d+(?:\.\d+)?", content)
                        if m:
                            time = float(m.group())

        if all(v is not None for v in [dataset, algo, length, dimension]):
            all_data.append({
                "dataset": dataset,
                "algorithm": algo,
                "length": length,
                "time": time,
                "dimension": dimension,
                "2opt_iters": opt_iters
            })

if not all_data:
    print("No valid data found.")
else:
    # === STEP 2: DataFrame 생성 및 정렬 ===
    df = pd.DataFrame(all_data)

    # 알고리즘 순서: OPT 먼저, 나머지 알파벳 순
    algos = sorted(set(row["algorithm"] for row in all_data if row["algorithm"] != "OPT"))
    algo_order = ["OPT"] + algos

    # 정렬: dimension > dataset > algorithm (with custom order)
    df.sort_values(
        by=["dimension", "dataset", "algorithm"],
        key=lambda x: x if x.name != "algorithm" else pd.Categorical(x, categories=algo_order, ordered=True),
        inplace=True
    )

    # === STEP 3: 포맷 변환 ===
    df["length"] = df["length"].map(lambda x: f"{int(x):d}")
    df["time"] = df["time"].apply(
        lambda x: f"{float(x):.6f}" if pd.notnull(x) and str(x).strip() != "" else ""
    ).astype(str)
    df["dimension"] = df["dimension"].map(lambda x: f"{int(x):d}")
    df["2opt_iters"] = df["2opt_iters"].astype(str)

    # === STEP 4: Markdown 저장 ===
    table = tabulate(df, headers='keys', tablefmt='pipe', showindex=False)
    with open(os.path.join(output_dir, "summary_table.md"), "w") as f:
        f.write(table)

    # === STEP 5: CSV 저장 ===
    df.to_csv(os.path.join(output_dir, "summary_table.csv"), index=False)

    print("[INFO] Markdown and CSV summary tables saved to 'summary/'")
