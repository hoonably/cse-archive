from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Dict, List, Type
import copy
import numpy as np

Array = np.ndarray


@dataclass
class OptimEnv:
    """Base class for differentiable optimization environments."""
    name: str
    display_name: str
    dim: int
    initial_points: List[Array]
    budget: int
    target_loss: float = 0.0
    divergence_threshold: float = 1e12
    xlim: tuple[float, float] = (-3.0, 3.0)
    ylim: tuple[float, float] = (-3.0, 3.0)

    def loss(self, x: Array) -> float:
        raise NotImplementedError

    def true_grad(self, x: Array) -> Array:
        raise NotImplementedError

    def grad(self, x: Array, rng: np.random.Generator) -> Array:
        return self.true_grad(x)

    def optimal_points(self) -> List[Array]:
        return []


@dataclass
class QuadraticEnv(OptimEnv):
    A: Array = None
    b: Array = None
    c: float = 0.0
    grad_noise: float = 0.0

    def __post_init__(self) -> None:
        self.A = np.asarray(self.A, dtype=float)
        self.b = np.asarray(self.b, dtype=float)

    def loss(self, x: Array) -> float:
        x = np.asarray(x, dtype=float)
        return float(0.5 * x @ self.A @ x + self.b @ x + self.c)

    def true_grad(self, x: Array) -> Array:
        return self.A @ np.asarray(x, dtype=float) + self.b

    def grad(self, x: Array, rng: np.random.Generator) -> Array:
        g = self.true_grad(x)
        if self.grad_noise > 0:
            g = g + rng.normal(0.0, self.grad_noise, size=g.shape)
        return g

    def optimal_points(self) -> List[Array]:
        try:
            return [np.linalg.solve(self.A, -self.b)]
        except np.linalg.LinAlgError:
            return []


@dataclass
class PlateauEnv(OptimEnv):
    """Flat plateau: f(x)=sum log(1+x_i^2/scale^2)."""
    scale: float = 1.0
    grad_noise: float = 0.0

    def loss(self, x: Array) -> float:
        x = np.asarray(x, dtype=float)
        return float(np.sum(np.log1p((x / self.scale) ** 2)))

    def true_grad(self, x: Array) -> Array:
        x = np.asarray(x, dtype=float)
        return 2.0 * x / (self.scale**2 + x**2)

    def grad(self, x: Array, rng: np.random.Generator) -> Array:
        g = self.true_grad(x)
        if self.grad_noise > 0:
            g = g + rng.normal(0.0, self.grad_noise, size=g.shape)
        return g

    def optimal_points(self) -> List[Array]:
        return [np.zeros(self.dim)]


@dataclass
class RosenbrockEnv(OptimEnv):
    a: float = 1.0
    b_rosen: float = 100.0
    grad_noise: float = 0.0

    def loss(self, x: Array) -> float:
        x0, x1 = float(x[0]), float(x[1])
        return float((self.a - x0) ** 2 + self.b_rosen * (x1 - x0**2) ** 2)

    def true_grad(self, x: Array) -> Array:
        x0, x1 = float(x[0]), float(x[1])
        d0 = -2.0 * (self.a - x0) - 4.0 * self.b_rosen * x0 * (x1 - x0**2)
        d1 = 2.0 * self.b_rosen * (x1 - x0**2)
        return np.array([d0, d1], dtype=float)

    def grad(self, x: Array, rng: np.random.Generator) -> Array:
        g = self.true_grad(x)
        if self.grad_noise > 0:
            g = g + rng.normal(0.0, self.grad_noise, size=g.shape)
        return g

    def optimal_points(self) -> List[Array]:
        return [np.array([self.a, self.a**2], dtype=float)]


@dataclass
class NoisySaddleEnv(OptimEnv):
    """Saddle escape environment with two global minima.

    f(x,y)=0.25*x^4 - 0.5*x^2 + 0.5*y^2 + 0.25.
    Minima are at (-1,0) and (1,0). The saddle is near (0,0).
    """
    grad_noise: float = 0.0

    def loss(self, x: Array) -> float:
        x0, x1 = float(x[0]), float(x[1])
        return float(0.25 * x0**4 - 0.5 * x0**2 + 0.5 * x1**2 + 0.25)

    def true_grad(self, x: Array) -> Array:
        x0, x1 = float(x[0]), float(x[1])
        return np.array([x0**3 - x0, x1], dtype=float)

    def grad(self, x: Array, rng: np.random.Generator) -> Array:
        g = self.true_grad(x)
        if self.grad_noise > 0:
            g = g + rng.normal(0.0, self.grad_noise, size=g.shape)
        return g

    def optimal_points(self) -> List[Array]:
        return [np.array([-1.0, 0.0]), np.array([1.0, 0.0])]


class BaseOptimizer:
    name = "BaseOptimizer"

    def reset(self, dim: int) -> None:
        pass

    def step(self, x: Array, grad: Array, t: int) -> Array:
        raise NotImplementedError


class VanillaGD(BaseOptimizer):
    """Provided baseline optimizer. Students do not need to modify this."""
    name = "Vanilla GD"

    def __init__(self, lr: float = 1e-3):
        self.lr = lr

    def step(self, x: Array, grad: Array, t: int) -> Array:
        return x - self.lr * grad


def run_optimizer(
    env: OptimEnv,
    optimizer: BaseOptimizer,
    x0: Array,
    seed: int,
    record_every: int = 1,
) -> Dict[str, Array]:
    rng = np.random.default_rng(seed)
    x = np.asarray(x0, dtype=float).copy()
    optimizer = copy.deepcopy(optimizer)
    optimizer.reset(env.dim)

    losses, grad_norms, xs = [], [], []
    diverged = False

    for t in range(1, env.budget + 1):
        current_loss = env.loss(x)
        if not np.isfinite(current_loss) or abs(current_loss) > env.divergence_threshold:
            diverged = True
            break

        g = env.grad(x, rng)
        if not np.all(np.isfinite(g)):
            diverged = True
            break

        if t == 1 or t % record_every == 0 or t == env.budget:
            losses.append(float(current_loss))
            grad_norms.append(float(np.linalg.norm(g)))
            xs.append(x.copy())

        try:
            x_next = optimizer.step(x.copy(), g.copy(), t)
        except NotImplementedError:
            raise
        x_next = np.asarray(x_next, dtype=float)
        if x_next.shape != x.shape or not np.all(np.isfinite(x_next)):
            diverged = True
            break
        x = x_next

    final_loss = env.loss(x) if not diverged and np.all(np.isfinite(x)) else env.divergence_threshold
    if not np.isfinite(final_loss):
        final_loss = env.divergence_threshold

    if len(xs) == 0:
        xs = [np.asarray(x0, dtype=float)]
        losses = [env.divergence_threshold]
        grad_norms = [env.divergence_threshold]

    return {
        "losses": np.asarray(losses, dtype=float),
        "grad_norms": np.asarray(grad_norms, dtype=float),
        "xs": np.stack(xs, axis=0),
        "final_x": np.asarray(x, dtype=float),
        "final_loss": np.array([float(final_loss)]),
        "diverged": np.array([bool(diverged)]),
    }


def robust_score_from_losses(losses: Array, target_loss: float, diverged: bool) -> float:
    losses = np.asarray(losses, dtype=float)
    excess = np.maximum(losses - target_loss, 0.0)
    log_excess = np.log1p(excess)
    auc = float(np.mean(log_excess))
    final = float(log_excess[-1])
    penalty = 10.0 if diverged else 0.0
    return auc + final + penalty


def evaluate_optimizer(envs: List[OptimEnv], optimizer_factory: Callable[[], BaseOptimizer], seeds: List[int]) -> Dict[str, object]:
    per_env = []
    all_scores = []
    for env in envs:
        scores, finals, divs = [], [], []
        for seed in seeds:
            for init_idx, x0 in enumerate(env.initial_points):
                result = run_optimizer(env, optimizer_factory(), x0=x0, seed=1000 * seed + init_idx)
                diverged = bool(result["diverged"][0])
                score = robust_score_from_losses(result["losses"], env.target_loss, diverged)
                scores.append(score)
                finals.append(float(result["final_loss"][0]))
                divs.append(diverged)
        per_env.append({
            "env_name": env.name,
            "avg_score": float(np.mean(scores)),
            "std_score": float(np.std(scores, ddof=1)) if len(scores) > 1 else 0.0,
            "avg_final_loss": float(np.mean(finals)),
            "divergence_rate": float(np.mean(divs)),
        })
        all_scores.extend(scores)
    return {
        "per_env": per_env,
        "avg_score_all": float(np.mean(all_scores)),
        "std_score_all": float(np.std(all_scores, ddof=1)) if len(all_scores) > 1 else 0.0,
    }
