from __future__ import annotations

from typing import List
from bandit_core import BanditEnv


def get_public_envs() -> List[BanditEnv]:
    """
    Public environments for vsco debugging and analysis.

    The five environments are designed to expose different issues:
    1. basic setting with a clear best arm
    2. small-gap setting where exploration matters
    3. high-variance best arm
    4. deceptive high-variance suboptimal arm
    5. many-arm mixed-difficulty setting
    """
    return [
        BanditEnv(
            name="env1_basic_clear_best",
            means=[0.40, 0.50, 0.60],
            stds=[0.10, 0.10, 0.10],
        ),
        BanditEnv(
            name="env2_small_gap",
            means=[0.500, 0.515, 0.530, 0.525],
            stds=[0.10, 0.10, 0.10, 0.10],
        ),
        BanditEnv(
            name="env3_high_variance_best_arm",
            means=[0.60, 0.66, 0.55, 0.58],
            stds=[0.05, 0.30, 0.05, 0.10],
        ),
        BanditEnv(
            name="env4_deceptive_high_variance_suboptimal",
            means=[0.64, 0.60, 0.70, 0.66],
            stds=[0.45, 0.05, 0.05, 0.08],
        ),
        BanditEnv(
            name="env5_many_arms_mixed",
            means=[0.42, 0.48, 0.52, 0.56, 0.59, 0.61, 0.63, 0.64],
            stds=[0.10, 0.20, 0.05, 0.25, 0.10, 0.30, 0.05, 0.12],
        ),
    ]
