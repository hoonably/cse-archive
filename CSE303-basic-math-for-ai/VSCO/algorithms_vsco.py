from __future__ import annotations

from typing import Dict
import numpy as np
from bandit_core import BanditEnv


def vsco_algorithm(env: BanditEnv, horizon: int, rng: np.random.Generator) -> Dict[str, np.ndarray]:
    """
    TODO:
    Implement your own exploration strategy.

    Suggested score form:
        score_i(t) = sample_mean_i(t) + bonus_i(t)
    """
    K = env.K
    counts = np.zeros(K, dtype=int)
    reward_sums = np.zeros(K, dtype=float)
    reward_sq_sums = np.zeros(K, dtype=float)

    actions = []
    rewards = []

    #! UCB hyper-parameters ====================================
    initial_pulls_per_arm = min(4, max(1, horizon // (20 * K)))    
    confidence_scale = 0.12 * (horizon / (horizon + 25.0))
    best_bonus_weight = 0.95
    #! =========================================================

    for t in range(horizon):
        scores = np.zeros(K, dtype=float)

        #! Check if we are in the initial warm-up phase
        warming_up = np.min(counts) < initial_pulls_per_arm

        if warming_up:
            #! Warm-up phase: Assign scores only to arms that haven't met the minimum pull count
            for i in range(K):
                if counts[i] < initial_pulls_per_arm:
                    scores[i] = 1e9 - counts[i]
                else:
                    scores[i] = -np.inf
        else:
            #! Calculate means, stds, and bonuses
            means = reward_sums / counts
            stds = np.sqrt(np.maximum(0.0, reward_sq_sums / counts - means**2))
            bonuses = confidence_scale * np.sqrt(np.log(t + 1) / counts) * np.clip(stds / 0.10, 0.50, 1.50)
            best_arm = int(np.argmax(means))

            #! UCB exploration and pruning
            for i in range(K):
                if i == best_arm:
                    scores[i] = means[i] + best_bonus_weight * bonuses[i]
                elif means[i] + bonuses[i] >= means[best_arm] - bonuses[best_arm]:
                    scores[i] = means[i] + bonuses[i]
                else:
                    scores[i] = -np.inf

        arm = int(np.argmax(scores))
        r = env.pull(arm, rng)

        counts[arm] += 1
        reward_sums[arm] += r
        reward_sq_sums[arm] += r * r

        actions.append(arm)
        rewards.append(r)

    return {"actions": np.asarray(actions, dtype=int), "rewards": np.asarray(rewards, dtype=float)}
