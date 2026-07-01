# 🗺️ Traveling Salesman Problem (TSP) Solver

---

## 🧠 Highlights
<p float="left"> <img src="./tour_image/a280/Flow_kNN-a280.png" alt="Flow_kNN-a280" width="48%" /> <img src="./tour_image/a280/Flow_kNN(+2opt)-a280.png" alt="Flow_kNN(+2opt)-a280" width="48%" /> </p>

<p float="left"> <img src="./tour_image/mona_lisa100K/Flow_kNN-mona_lisa100K.png" alt="Flow_kNN-mona_lisa100K" width="48%" /> <img src="./tour_image/mona_lisa100K/MST-mona_lisa100K.png" alt="MST-mona_lisa100K" width="48%" /> </p>

- 🧭 Exact Method: Held-Karp for small instances (n ≤ 20)
- ⚡ Fastest Practical: Greedy + 2-opt (fast + high-quality)
- 🔁 New Hybrid Algorithm: Flow-based initialization + 2-opt refinement
- 📈 Notable Outlier: MST shows poor scaling on mona_lisa100K due to rigid traversal and long edges
- 🧪 Evaluation: runtime, quality, scalability on 5 datasets



---

## 📘 Project Overview

This project was conducted for **CSE331: Algorithm** at **UNIST**.
We implemented and evaluated the following algorithms:

| Category     | Algorithms                                                    |
| ------------ | ------------------------------------------------------------- |
| Exact        | Held-Karp (Dynamic Programming)                               |
| Approximate  | MST-based 2-Approx, Greedy Nearest-Neighbor                   |
| Local Search | 2-Opt Optimization                                            |
| Heuristic    | Flow-based Cycle Cover (MCMF), Flow + 2opt, Flow_kNN (+2opt) |

---

## 📁 Directory Structure

```bash
.
├── dataset/             # Input TSP files (TSPLIB format)
├── tour_paths/          # Output .tour files for each algorithm and dataset
├── tour_image/          # Visualized paths (PNG)
├── summary/             # Summary tables (.csv, .md)
├── *.cpp                # Algorithm implementations
├── *.h                  # Shared utilities (util.h, util2.h)
├── _make_summary.py     # CSV/MD aggregator
├── _visualize_tsp_paths.py  # Tour plotter
└── pdf/                 # Project manual and references
```

---

## ⚙️ How to Run

Each algorithm is defined in a standalone `.cpp` file and contains a hardcoded main loop.

### 🔧 Example: Run Greedy + 2opt

```bash
g++ -std=c++17 -O2 Greedy.cpp -o greedy
./greedy
```

### 🛠 Internal Configuration

Inside each file, you’ll find:

```cpp
#include "util.h"
// #include "util2.h"  // ← use this for 100K-city dataset

vector<string> files = {
    "weird20.tsp", "a280.tsp", "xql662.tsp", "kz9976.tsp",
    // "mona_lisa100K.tsp"
};

bool use_2opt = true;  // enable local optimization
```

> 💡 To test large-scale instances (`mona_lisa100K.tsp`), switch to `util2.h` and disable 2-opt (`use_2opt = false`) for memory efficiency.

---

## 📊 Summary of Results

|   Dataset (Opt)      | Algorithm | Base Len  | Approx     | Time (s) |  2opt Len   | 2opt Approx | 2opt Time (s) | 2opt Iters |
| -------------------- | --------- | --------- | ---------- | -------- | ----------- | ---------- | -------- | ---------- |
| **a280 (2579)**      | Random    | 33736     | 13.0741    | –        | 2774        | 1.0756     | 0.0229   | 1368       |
|                      | Greedy    | 3157      | **1.2244** | 0.0001   | 2767        | 1.0729     | 0.0030   | 57         |
|                      | MST       | 3492      | 1.3540     | 0.0003   | 2908        | 1.1276     | 0.0045   | 80         |
|                      | Flow      | 3417      | 1.3251     | 0.0162   | 2705        | 1.0489     | 0.0190   | 66         |
|                      | Flow\_kNN | 3348      | 1.2979     | 0.0067   | **2696**    | **1.0453** | 0.0118   | 82         |
| **xql662 (2513)**    | Random    | 53168     | 21.1507    | –        | 2762        | 1.0989     | 0.2770   | 3945       |
|                      | Greedy    | 3124      | **1.2430** | 0.0008   | **2693**    | **1.0716** | 0.0320   | 116        |
|                      | MST       | 3593      | 1.4299     | 0.0012   | 2763        | 1.0996     | 0.0393   | 237        |
|                      | Flow      | 3862      | 1.5373     | 0.0641   | 2719        | 1.0819     | 0.0931   | 267        |
|                      | Flow\_kNN | 3931      | 1.5640     | 0.0341   | 2737        | 1.0893     | 0.0700   | 301        |
| **kz9976 (1061882)** | Random    | 133724845 | 125.9204   | –        | 1154441     | 1.0868     | 3582.80  | 119612     |
|                      | Greedy    | 1358249   | **1.2790** | 0.0616   | 1141502     | 1.0752     | 146.80   | 3340       |
|                      | MST       | 1456572   | 1.3719     | 0.1276   | 1162397     | 1.0947     | 171.80   | 4638       |
|                      | Flow      | 1707487   | 1.6081     | 210.41   | **1138579** | **1.0731** | 537.88   | 5619       |
|                      | Flow\_kNN | 1719092   | 1.6193     | 21.79    | 1146693     | 1.0799     | 318.39   | 6231       |


More results: [`summary/summary_table.csv`](summary/summary_table.csv)

---

## 🖼 Tour Visualizations

All solution tours are saved as `.png` in `tour_image/`.

```bash
tour_image/a280/Greedy(+2opt)-a280.png
tour_image/kz9976/Flow_kNN(+2opt)-kz9976.png
```

Use `_visualize_tsp_paths.py` to batch regenerate or customize.

---

## 🧪 Experimental Setup

* 💻 **Device**: MacMini (Apple M4, 16GB RAM)
* ⚙️ **Compiler**: `clang++ -std=c++17 -O2`
* 📊 **Datasets**:

  * weird20 (20 cities)
  * a280 (280 cities)
  * xql662 (662 cities)
  * kz9976 (9976 cities)
  * mona\_lisa100K (100,000 cities)

---

## 📎 Reference

Project Page: https://jeonghoonpark.com/project/traveling-salesman
