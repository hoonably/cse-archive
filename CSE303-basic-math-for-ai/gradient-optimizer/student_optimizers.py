from __future__ import annotations

import numpy as np
from optimization_core import Array, BaseOptimizer


class Momentum(BaseOptimizer):
    """Implement SGD with momentum.

    Suggested update:
        v_t = beta * v_{t-1} + grad_t
        x_{t+1} = x_t - lr * v_t
    """
    name = "Momentum"

    def __init__(self, lr: float = 1.5e-3, beta: float = 0.95):
        self.lr = lr
        self.beta = beta
        self.v = None

    def reset(self, dim: int) -> None:
        self.v = np.zeros(dim, dtype=float)

    def step(self, x: Array, grad: Array, t: int) -> Array:
        # TODO: implement Momentum update.
        # Replace the line below with your code.
        if self.v is None:
            self.v = np.zeros_like(x, dtype=float)
        self.v = self.beta * self.v + grad
        x_next = x - self.lr * self.v
        return x_next
        raise NotImplementedError("Momentum.step() is not implemented yet.")


class RMSProp(BaseOptimizer):
    """Implement RMSProp.

    Suggested update:
        s_t = beta * s_{t-1} + (1-beta) * grad_t^2
        x_{t+1} = x_t - lr * grad_t / (sqrt(s_t) + eps)
    """
    name = "RMSProp"

    def __init__(self, lr: float = 5e-2, beta: float = 0.999, eps: float = 5e-2):
        self.lr = lr
        self.beta = beta
        self.eps = eps
        self.s = None

    def reset(self, dim: int) -> None:
        self.s = np.zeros(dim, dtype=float)

    def step(self, x: Array, grad: Array, t: int) -> Array:
        # TODO: implement RMSProp update.
        # Replace the line below with your code.
        if self.s is None:
            self.s = np.zeros_like(x, dtype=float)
        self.s = self.beta * self.s + (1.0 - self.beta) * (grad ** 2)
        x_next = x - self.lr * grad / (np.sqrt(self.s) + self.eps)
        return x_next
        raise NotImplementedError("RMSProp.step() is not implemented yet.")


class Adam(BaseOptimizer):
    """Implement Adam.

    Suggested update:
        m_t = beta1 * m_{t-1} + (1-beta1) * grad_t
        v_t = beta2 * v_{t-1} + (1-beta2) * grad_t^2
        m_hat = m_t / (1 - beta1^t)
        v_hat = v_t / (1 - beta2^t)
        x_{t+1} = x_t - lr * m_hat / (sqrt(v_hat) + eps)
    """
    name = "Adam"

    def __init__(self, lr: float = 5e-2, beta1: float = 0.9, beta2: float = 0.99, eps: float = 1e-8):
        self.lr = lr
        self.beta1 = beta1
        self.beta2 = beta2
        self.eps = eps
        self.m = None
        self.v = None

    def reset(self, dim: int) -> None:
        self.m = np.zeros(dim, dtype=float)
        self.v = np.zeros(dim, dtype=float)

    def step(self, x: Array, grad: Array, t: int) -> Array:
        # TODO: implement Adam update with bias correction.
        # Replace the line below with your code.
        if self.m is None:
            self.m = np.zeros_like(x, dtype=float)
        if self.v is None:
            self.v = np.zeros_like(x, dtype=float)
        self.m = self.beta1 * self.m + (1.0 - self.beta1) * grad
        self.v = self.beta2 * self.v + (1.0 - self.beta2) * (grad ** 2)
        m_hat = self.m / (1.0 - self.beta1 ** t)
        v_hat = self.v / (1.0 - self.beta2 ** t)
        x_next = x - self.lr * m_hat / (np.sqrt(v_hat) + self.eps)
        return x_next
        raise NotImplementedError("Adam.step() is not implemented yet.")


class AdamW(BaseOptimizer):
    """Implement AdamW with decoupled weight decay.

    Suggested update:
        Adam step direction is computed as in Adam.
        x_{t+1} = x_t - lr * adam_direction - lr * weight_decay * x_t

    Note: this is decoupled weight decay, not L2 regularization added to grad.
    """
    name = "AdamW"

    def __init__(
        self,
        lr: float = 5e-2,
        beta1: float = 0.9,
        beta2: float = 0.99,
        eps: float = 1e-8,
        weight_decay: float = 1e-4,
    ):
        self.lr = lr
        self.beta1 = beta1
        self.beta2 = beta2
        self.eps = eps
        self.weight_decay = weight_decay
        self.m = None
        self.v = None

    def reset(self, dim: int) -> None:
        self.m = np.zeros(dim, dtype=float)
        self.v = np.zeros(dim, dtype=float)

    def step(self, x: Array, grad: Array, t: int) -> Array:
        # TODO: implement AdamW update with bias correction and decoupled weight decay.
        # Replace the line below with your code.
        if self.m is None:
            self.m = np.zeros_like(x, dtype=float)
        if self.v is None:
            self.v = np.zeros_like(x, dtype=float)
        self.m = self.beta1 * self.m + (1.0 - self.beta1) * grad
        self.v = self.beta2 * self.v + (1.0 - self.beta2) * (grad ** 2)
        m_hat = self.m / (1.0 - self.beta1 ** t)
        v_hat = self.v / (1.0 - self.beta2 ** t)
        adam_direction = m_hat / (np.sqrt(v_hat) + self.eps)
        x_next = x - self.lr * adam_direction - self.lr * self.weight_decay * x
        return x_next
        raise NotImplementedError("AdamW.step() is not implemented yet.")
