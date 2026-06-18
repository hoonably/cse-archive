from __future__ import annotations

from algorithms_baseline import greedy, epsilon_greedy, softmax_policy
from algorithms_vsco import vsco_algorithm
from bandit_core import evaluate_algorithm
from public_envs import get_public_envs

import numpy as np


def print_table(headers, rows):
    rows_str = [[str(cell) for cell in row] for row in rows]
    widths = [len(str(h)) for h in headers]
    for row in rows_str:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))

    def fmt_row(row):
        return " | ".join(str(cell).ljust(widths[i]) for i, cell in enumerate(row))

    separator = "-+-".join("-" * w for w in widths)

    print(fmt_row(headers))
    print(separator)
    for row in rows_str:
        print(fmt_row(row))


def print_environment_results(envs, algos, horizon, seeds, evaluate_algorithm, title):
    n = len(seeds)

    print("=" * 108)
    print(title)
    print("=" * 108)
    print(f"Horizon: {horizon}, number of seeds: {n}")
    print("Metric: expected cumulative regret, averaged across seeds")

    overall_scores = {name: [] for name in algos}
    overall_regrets = {name: [] for name in algos}

    for env in envs:
        print(f"\nEnvironment: {env.name}")
        print(f"Means: {env.means.tolist()}")
        print(f"Stds : {env.stds.tolist()}")
        print(f"Best arm: {env.best_arm}, best mean: {env.best_mean:.3f}")

        env_results = []

        for algo_name, algo_fn in algos.items():
            summary = evaluate_algorithm([env], algo_fn, horizon=horizon, seeds=seeds)
            res = summary["per_env"][0]

            reward_se = res["std_total_reward"] / np.sqrt(n)
            regret_se = res["std_final_regret"] / np.sqrt(n)

            env_results.append({
                "algo_name": algo_name,
                "avg_reward": res["avg_total_reward"],
                "reward_se": reward_se,
                "avg_final_regret": res["avg_final_regret"],
                "regret_se": regret_se,
            })

        ranked = sorted(env_results, key=lambda x: x["avg_final_regret"])
        rows = []

        for rank, item in enumerate(ranked, start=1):
            overall_scores[item["algo_name"]].append(rank)
            overall_regrets[item["algo_name"]].append(item["avg_final_regret"])
            rows.append([
                rank,
                item["algo_name"],
                f"{item['avg_reward']:.3f}",
                f"{item['reward_se']:.3f}",
                f"{item['avg_final_regret']:.3f}",
                f"{item['regret_se']:.3f}",
            ])

        print_table(
            headers=["Rank", "Algorithm", "Avg reward", "Reward SE", "Avg final regret", "Regret SE"],
            rows=rows,
        )

    leaderboard_rows = []
    for algo_name in algos:
        avg_rank = float(np.mean(overall_scores[algo_name]))
        total_rank_points = int(np.sum(overall_scores[algo_name]))
        avg_regret = float(np.mean(overall_regrets[algo_name]))
        leaderboard_rows.append([algo_name, avg_rank, total_rank_points, avg_regret])

    leaderboard_rows.sort(key=lambda x: (x[1], x[2], x[3], x[0]))
    formatted_rows = [
        [rank, row[0], f"{row[1]:.3f}", row[2], f"{row[3]:.3f}"]
        for rank, row in enumerate(leaderboard_rows, start=1)
    ]

    print("\n" + "=" * 108)
    print("Overall leaderboard (lower is better)")
    print("=" * 108)
    print_table(
        headers=["Rank", "Algorithm", "Average rank", "Total rank points", "Avg regret"],
        rows=formatted_rows,
    )

def main() -> None:
    envs = get_public_envs()
    horizon = 10000
    seeds = list(range(10))

    algos = {
        "greedy": greedy,
        "epsilon_greedy": epsilon_greedy,
        "softmax_policy": softmax_policy,
        "vsco_algorithm": vsco_algorithm,
    }

    print_environment_results(
        envs=envs,
        algos=algos,
        horizon=horizon,
        seeds=seeds,
        evaluate_algorithm=evaluate_algorithm,
        title="Public evaluation (per environment)",
    )


if __name__ == "__main__":
    main()
