from __future__ import annotations

from typing import Dict
import numpy as np
from bandit_core import BanditEnv


def greedy(env: BanditEnv, horizon: int, rng: np.random.Generator) -> Dict[str, np.ndarray]:
    K = env.K
    counts = np.zeros(K, dtype=int)
    reward_sums = np.zeros(K, dtype=float)

    actions = []
    rewards = []

    for t in range(horizon):
        if np.any(counts == 0):
            arm = int(np.argmin(counts))
        else:
            means = reward_sums / counts
            arm = int(np.argmax(means))

        r = env.pull(arm, rng)
        counts[arm] += 1
        reward_sums[arm] += r

        actions.append(arm)
        rewards.append(r)

    return {"actions": np.asarray(actions, dtype=int), "rewards": np.asarray(rewards, dtype=float)}


def epsilon_greedy(
    env: BanditEnv,
    horizon: int,
    rng: np.random.Generator,
    epsilon: float = 0.10,
) -> Dict[str, np.ndarray]:
    K = env.K
    counts = np.zeros(K, dtype=int)
    reward_sums = np.zeros(K, dtype=float)

    actions = []
    rewards = []

    for t in range(horizon):
        if np.any(counts == 0):
            arm = int(np.argmin(counts))
        elif rng.random() < epsilon:
            arm = int(rng.integers(0, K))
        else:
            means = reward_sums / counts
            arm = int(np.argmax(means))

        r = env.pull(arm, rng)
        counts[arm] += 1
        reward_sums[arm] += r

        actions.append(arm)
        rewards.append(r)

    return {"actions": np.asarray(actions, dtype=int), "rewards": np.asarray(rewards, dtype=float)}


def softmax_policy(
    env: BanditEnv,
    horizon: int,
    rng: np.random.Generator,
    temperature: float = 0.01,
) -> Dict[str, np.ndarray]:
    """
    Softmax action selection based on empirical sample means.

    At each round, the probability of choosing arm i is

        p_i = exp(mean_i / temperature) / sum_j exp(mean_j / temperature)

    Notes:
    - Smaller temperature makes the policy more greedy.
    - Larger temperature makes the policy more exploratory/random.
    - Each arm is pulled once initially to avoid undefined means.
    """
    if temperature <= 0:
        raise ValueError("temperature must be positive.")

    K = env.K
    counts = np.zeros(K, dtype=int)
    reward_sums = np.zeros(K, dtype=float)

    actions = []
    rewards = []

    for t in range(horizon):
        if np.any(counts == 0):
            arm = int(np.argmin(counts))
        else:
            means = reward_sums / counts

            logits = means / temperature
            logits = logits - np.max(logits)
            probs = np.exp(logits)
            probs = probs / np.sum(probs)

            arm = int(rng.choice(K, p=probs))

        r = env.pull(arm, rng)
        counts[arm] += 1
        reward_sums[arm] += r

        actions.append(arm)
        rewards.append(r)

    return {"actions": np.asarray(actions, dtype=int), "rewards": np.asarray(rewards, dtype=float)}
