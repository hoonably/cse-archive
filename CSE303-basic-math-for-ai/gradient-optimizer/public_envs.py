from __future__ import annotations

from typing import List
import numpy as np
from optimization_core import OptimEnv, QuadraticEnv, PlateauEnv, RosenbrockEnv, NoisySaddleEnv


def rotated_quadratic_matrix(lam1: float, lam2: float, angle_deg: float) -> np.ndarray:
    theta = np.deg2rad(angle_deg)
    R = np.array([[np.cos(theta), -np.sin(theta)], [np.sin(theta), np.cos(theta)]])
    return R @ np.diag([lam1, lam2]) @ R.T


def get_public_envs() -> List[OptimEnv]:
    """Four public environments used for this homework.

    No hidden environments are used. The goal is not to beat a secret test set,
    but to correctly implement and analyze several standard optimizers.
    """
    return [
        QuadraticEnv(
            name="env1_zigzag",
            display_name="Env 1: Zig-Zag / Ill-Conditioned Quadratic",
            dim=2,
            budget=2000,
            target_loss=0.0,
            A=rotated_quadratic_matrix(400.0, 1.0, 35.0),
            b=np.zeros(2),
            c=0.0,
            initial_points=[np.array([1.5, 2.5])],
            xlim=(-3.0, 3.0),
            ylim=(-3.0, 3.0),
            divergence_threshold=1e10,
        ),
        PlateauEnv(
            name="env2_plateau",
            display_name="Env 2: Plateau / Small Gradients",
            dim=2,
            budget=1200,
            target_loss=0.0,
            scale=0.45,
            grad_noise=0.0,
            initial_points=[np.array([6.0, -5.5])],
            xlim=(-7.0, 7.0),
            ylim=(-7.0, 7.0),
            divergence_threshold=1e10,
        ),
        RosenbrockEnv(
            name="env3_rosenbrock",
            display_name="Env 3: Rosenbrock / Curved Valley",
            dim=2,
            budget=2200,
            target_loss=0.0,
            a=1.0,
            b_rosen=100.0,
            initial_points=[np.array([-1.5, 1.8])],
            xlim=(-2.2, 2.2),
            ylim=(-1.0, 3.0),
            divergence_threshold=1e10,
        ),
        NoisySaddleEnv(
            name="env4_noisy_saddle_escape",
            display_name="Env 4: Noisy Saddle Escape",
            dim=2,
            budget=1200,
            target_loss=0.0,
            grad_noise=0.025,
            initial_points=[np.array([0.03, 2.7])],
            xlim=(-2.2, 2.2),
            ylim=(-3.0, 3.0),
            divergence_threshold=1e10,
        ),
    ]
