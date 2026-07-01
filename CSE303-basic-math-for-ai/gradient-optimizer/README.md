# Gradient Optimizer: Momentum, RMSProp, Adam, and AdamW

A small optimizer comparison assignment for two-dimensional differentiable loss landscapes.

This assignment implements and compares:
- Momentum
- RMSProp
- Adam
- AdamW

The public environments cover ill-conditioned curvature, plateaus, Rosenbrock-style curved valleys, and noisy saddle escape.

---

## Optimizer Trajectories

<p align="center">
  <img src="plots/gifs/env1_zigzag_optimizer_comparison.gif" width="47%" alt="Zig-zag quadratic optimizer trajectory comparison">
  <img src="plots/gifs/env2_plateau_optimizer_comparison.gif" width="47%" alt="Plateau optimizer trajectory comparison">
</p>

<p align="center">
  <img src="plots/gifs/env3_rosenbrock_optimizer_comparison.gif" width="47%" alt="Rosenbrock optimizer trajectory comparison">
  <img src="plots/gifs/env4_noisy_saddle_escape_optimizer_comparison.gif" width="47%" alt="Noisy saddle optimizer trajectory comparison">
</p>

---

## Results

Lower robust score is better. Adam achieved the best average score, with AdamW nearly tied. RMSProp was strongest on three public landscapes but struggled on the Rosenbrock valley.

| Optimizer | Avg. robust score | Std. |
| --- | ---: | ---: |
| Adam | **0.1600** | 0.0813 |
| AdamW | 0.1603 | 0.0815 |
| Momentum | 0.2446 | 0.2312 |
| RMSProp | 0.3873 | 0.6443 |
| Vanilla GD | 1.8505 | 1.7982 |

| Environment | Best optimizer | Best score | Avg. final loss |
| --- | --- | ---: | ---: |
| `env1_zigzag` | RMSProp | **0.031** | 5.84e-08 |
| `env2_plateau` | RMSProp | **0.040** | 0.00396 |
| `env3_rosenbrock` | Momentum | **0.081** | 4.98e-30 |
| `env4_noisy_saddle_escape` | RMSProp | **0.004** | 0.000169 |

---

## How to Reproduce

```bash
conda env create -f environment.yml
conda activate cse30301
```

```bash
python visualize.py
```

---

## Files

```text
student_optimizers.py   # Momentum, RMSProp, Adam, and AdamW implementations
optimization_core.py    # Optimizer runner, scoring, and base environments
public_envs.py          # Four public optimization environments
visualize.py            # Trajectory GIF and final-figure renderer
plots/gifs/             # Animated optimizer comparisons
plots/final_figures/    # Final-iteration snapshots
report.pdf              # Short report
00_manual.pdf           # Assignment manual
```
