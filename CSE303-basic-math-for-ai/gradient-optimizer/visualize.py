from __future__ import annotations

import os
from typing import Dict, List

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from PIL import Image

from optimization_core import VanillaGD, run_optimizer
from public_envs import get_public_envs
from student_optimizers import Momentum, RMSProp, Adam, AdamW

# Rendering options.
# MAX_GIF_FRAMES controls the number of animation frames. The optimizer itself
# still runs for the full environment budget, and the frames are sampled across
# the entire trajectory, including the final iteration.
GIF_FPS = 10
MAX_GIF_FRAMES = 24
GRID_SIZE = 140
FIG_SIZE = (8.0, 8.0)
FIG_DPI = 80
FINAL_FIG_DPI = 180

OPT_COLORS = {
    "Vanilla GD": "#1f77b4",
    "Momentum": "#2ca02c",
    "RMSProp": "#8c564b",
    "Adam": "#d62728",
    "AdamW": "#17becf",
}


def fig_to_rgb_array(fig: plt.Figure) -> np.ndarray:
    """Convert a Matplotlib figure to an RGB numpy array.

    This implementation is robust to macOS/Retina backends where the physical
    canvas resolution can differ from fig.canvas.get_width_height().
    """
    fig.canvas.draw()
    rgba = np.asarray(fig.canvas.buffer_rgba(), dtype=np.uint8)
    return rgba[:, :, :3].copy()


def make_landscape_grid(env):
    xs = np.linspace(env.xlim[0], env.xlim[1], GRID_SIZE)
    ys = np.linspace(env.ylim[0], env.ylim[1], GRID_SIZE)
    X, Y = np.meshgrid(xs, ys)
    Z = np.zeros_like(X)
    for i in range(GRID_SIZE):
        for j in range(GRID_SIZE):
            Z[i, j] = env.loss(np.array([X[i, j], Y[i, j]], dtype=float))

    finite = np.isfinite(Z)
    if not np.any(finite):
        raise RuntimeError(f"Landscape for {env.name} produced no finite values.")

    # Clip extreme values so contours remain visually informative.
    cap = np.percentile(Z[finite], 92)
    Z = np.clip(Z, np.min(Z[finite]), cap)
    return X, Y, Z


def collect_trajectories(env):
    factories = {
        "Vanilla GD": lambda: VanillaGD(lr=1e-3),
        "Momentum": lambda: Momentum(),
        "RMSProp": lambda: RMSProp(),
        "Adam": lambda: Adam(),
        "AdamW": lambda: AdamW(),
    }

    x0 = env.initial_points[0]
    trajectories: Dict[str, np.ndarray] = {}
    skipped: Dict[str, str] = {}

    for name, factory in factories.items():
        try:
            result = run_optimizer(env, factory(), x0=x0, seed=0, record_every=1)
            trajectories[name] = result["xs"]
        except NotImplementedError as e:
            skipped[name] = str(e)

    return trajectories, skipped


def get_frame_indices(max_len: int) -> List[int]:
    if max_len <= MAX_GIF_FRAMES:
        return list(range(max_len))
    return np.linspace(0, max_len - 1, MAX_GIF_FRAMES, dtype=int).tolist()


def setup_axes(env, X, Y, Z, dpi: int):
    fig, ax = plt.subplots(figsize=FIG_SIZE, dpi=dpi)
    fig.patch.set_facecolor("white")
    ax.set_facecolor("white")

    levels = np.linspace(float(np.min(Z)), float(np.max(Z)), 45)
    ax.contour(X, Y, Z, levels=levels, cmap="YlGn", linewidths=1.15, alpha=0.9)

    for k, p in enumerate(env.optimal_points()):
        ax.scatter(
            p[0], p[1], marker="*", s=430, c="black", edgecolors="black",
            linewidths=0.8, zorder=30, label="Minimum" if k == 0 else None
        )

    start = env.initial_points[0]
    ax.scatter(
        start[0], start[1], marker="o", s=135, c="#d98c3f", edgecolors="black",
        linewidths=1.0, zorder=28, label="Start"
    )

    ax.set_xlim(env.xlim)
    ax.set_ylim(env.ylim)
    ax.set_xlabel(r"$\theta_1$", fontsize=18)
    ax.set_ylabel(r"$\theta_2$", fontsize=18)
    ax.tick_params(labelsize=13)
    fig.subplots_adjust(left=0.12, right=0.98, bottom=0.10, top=0.91)

    return fig, ax


def add_legend(ax, trajectories):
    legend_elements: List[Line2D] = [
        Line2D([0], [0], marker="*", color="w", label="Minimum",
               markerfacecolor="black", markeredgecolor="black", markersize=18),
        Line2D([0], [0], marker="o", color="w", label="Start",
               markerfacecolor="#d98c3f", markeredgecolor="black", markersize=11),
    ]

    for name in trajectories.keys():
        color = OPT_COLORS.get(name, None)
        legend_elements.append(Line2D([0], [0], color=color, lw=3.0, label=name))

    ax.legend(handles=legend_elements, loc="upper right", fontsize=12, framealpha=0.95)


def create_gif(env, output_dir="plots/gifs"):
    os.makedirs(output_dir, exist_ok=True)
    trajectories, skipped = collect_trajectories(env)

    if len(trajectories) == 0:
        print(f"[skip] {env.name}: no implemented optimizers available.")
        return

    X, Y, Z = make_landscape_grid(env)
    max_len = max(len(t) for t in trajectories.values())
    frame_indices = get_frame_indices(max_len)

    fig, ax = setup_axes(env, X, Y, Z, dpi=FIG_DPI)
    add_legend(ax, trajectories)

    # Create persistent line/current-point artists and update them each frame.
    line_artists = {}
    point_artists = {}
    for name, traj in trajectories.items():
        color = OPT_COLORS.get(name, None)
        line, = ax.plot([], [], color=color, linewidth=2.7, alpha=0.95, zorder=12)
        point = ax.scatter([], [], s=72, color=color, edgecolors="black", linewidths=0.7, zorder=22)
        line_artists[name] = line
        point_artists[name] = point

    title = ax.set_title("", fontsize=17, pad=12)

    frames = []
    for idx in frame_indices:
        for name, traj in trajectories.items():
            step_idx = min(idx, len(traj) - 1)
            current = traj[: step_idx + 1]
            line_artists[name].set_data(current[:, 0], current[:, 1])
            point_artists[name].set_offsets(current[-1].reshape(1, 2))

        title.set_text(f"{env.display_name} | Iteration {idx}")
        frames.append(fig_to_rgb_array(fig))

    plt.close(fig)

    gif_path = os.path.join(output_dir, f"{env.name}_optimizer_comparison.gif")
    pil_frames = [Image.fromarray(frame).convert("P", palette=Image.ADAPTIVE, colors=256) for frame in frames]
    duration_ms = int(1000 / GIF_FPS)
    pil_frames[0].save(
        gif_path,
        save_all=True,
        append_images=pil_frames[1:],
        duration=duration_ms,
        loop=0,
        optimize=False,
        disposal=2,
    )
    print(f"Saved GIF: {gif_path}")

    save_final_figure(env, X, Y, Z, trajectories)

    if skipped:
        print("  Skipped TODO optimizers:", ", ".join(skipped.keys()))


def save_final_figure(env, X, Y, Z, trajectories, output_dir="plots/final_figures"):
    """Save a high-resolution PNG snapshot of the final iteration."""
    os.makedirs(output_dir, exist_ok=True)

    fig, ax = setup_axes(env, X, Y, Z, dpi=FINAL_FIG_DPI)

    for name, traj in trajectories.items():
        color = OPT_COLORS.get(name, None)
        ax.plot(traj[:, 0], traj[:, 1], color=color, linewidth=2.7, alpha=0.95, zorder=12)
        ax.scatter(
            traj[-1, 0], traj[-1, 1], s=72, color=color,
            edgecolors="black", linewidths=0.7, zorder=22
        )

    add_legend(ax, trajectories)
    ax.set_title(f"{env.display_name} | Final Iteration", fontsize=17, pad=12)

    save_path = os.path.join(output_dir, f"{env.name}_final_iteration.png")
    fig.savefig(save_path, dpi=FINAL_FIG_DPI)
    plt.close(fig)
    print(f"Saved final figure: {save_path}")


def main():
    for env in get_public_envs():
        create_gif(env)


if __name__ == "__main__":
    main()
