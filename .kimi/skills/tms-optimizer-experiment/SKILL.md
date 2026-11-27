---
name: tms-optimizer-experiment
description: Experiment output management, directory structure, visualization standards, reproducibility conventions, and coding discipline enforcement for the tms_optimizer project. Use when running simulations, generating results, creating visualizations, managing experiment artifacts, writing or reviewing Python code, or modifying src/tms_optimizer/.
skill_role: workflow
---

# TMS Optimizer — Experiment Management & Output Conventions

Project root: `D:\djh\search_agent\tms_optimizer`

---

## 1. Golden Rule: One Experiment = One Directory

Every experiment run MUST have its own timestamped directory under `experiments/` or `outputs/`. **Never** dump PNGs, JSONs, or NPZs into the project root.

### Required directory structure per experiment

```
experiments/
└── 2026-05-17_143052_nsteps7_pop100_gen100_3targets/
    ├── config.json              # Exact config used (Pydantic dump)
    ├── metadata.json            # Run metadata (time, n_eval, seed, etc.)
    ├── results.npz              # Current vectors & objectives (see §3)
    ├── focal_areas.json         # Per-solution focal area data (optional, if generated)
    ├── log.txt                  # Console log / stdout capture
    └── plots/                   # STANDARD 7 figures (see §2)
        ├── 01_target_regions.png
        ├── 02_field_distribution.png
        ├── 03_coil_winding.png
        ├── 04_focus_areas.png
        ├── 05_pareto_front.png
        ├── 06_target2max.png
        └── 07_oa90.png
```

### Naming convention

```
{YYYY-MM-DD}_{HHMMSS}_{key_params}/
```

Key params should be concise but unambiguous:
- `nsteps7_pop100_gen100_3targets`
- `nsteps15_pop200_gen200_single`
- `nsteps25_pop200_gen500_2obj_CDP`
- `T017_2obj_CDP_gen500`

> **Why timestamp first?** Sorts chronologically in file explorer.
> **Why params in name?** Human-readable at a glance, no need to open config.json.

---

## 2. Standardized Visualization Outputs (MANDATORY)

**Every experiment** — whether NSGA-II optimization or loading a single current vector — MUST produce **exactly the same 7 figures** with fixed filenames. This ensures scientific reproducibility and avoids the "different runs produce different plots" problem.

### Required figures

| # | Filename | Content | Applies to |
|---|----------|---------|------------|
| 01 | `01_target_regions.png` | 3D sphere showing target ellipses, sampling points, and ellipse boundaries (3-view) | All experiments |
| 02 | `02_field_distribution.png` | Electric-field magnitude \|E\| on the **head radius r** (3D spherical surface + 3-view) | All experiments |
| 03 | `03_coil_winding.png` | **Streamfunction Ψ contours directly mapped onto the 3D coil sphere R**. Left: shaded surface + overlaid contour lines. Right: contour lines alone on wireframe sphere. | All experiments |
| 04 | `04_focus_areas.png` | Bar chart of focal areas per target (FWHM), with optional error bars from Pareto spread | All experiments |
| 05 | `05_pareto_front.png` | Pareto-front scatter. 3-obj: f1 vs f3, color=f2. 2-obj: f1 vs f2. | NSGA-II only |
| 06 | `06_target2max.png` | Bar chart of Target2Max per target; ideal=1.0 (red dashed line) | All experiments |
| 07 | `07_oa90.png` | Scatter of OA90 overstimulated area per solution (cm²) | All experiments |

### Critical rules

1. **Use the module** — do NOT hand-write plotting code in each script. Import from:
   ```python
   from tms_optimizer.visualization.standard_plots import save_standard_plots
   ```
   This guarantees identical figure sizes, color maps, and layouts across all experiments.

2. **E-field must be evaluated at `head_radius` r**, not `coil_radius` R. The 3D sphere in `02_field_distribution.png` must match the head model radius.

3. **Coil winding contours MUST be on the 3D sphere surface**, not flat θ-φ projections. Flat contours are not intuitive for spherical coil design. The `03_coil_winding.png` right panel must show contour lines plotted as 3D curves on the coil sphere wireframe.

4. **For single-vector simulations** (loading a known current vector), still produce all 7 figures. The Pareto-front figure can show a single-point scatter or a blank placeholder.

### Quick usage

```python
from tms_optimizer.visualization.standard_plots import save_standard_plots

saved_paths = save_standard_plots(
    "experiments/2026-05-17_143052_nsteps7_pop100_gen100_3targets",
    config=config,
    result=result,
    target_points_cell=target_points_cell,
    remaining_points=remaining_points,
    target_centers=target_centers,
    a_values=a_values,
    b_values=b_values,
    alpha_values=alpha_values,
    best_coeffs=None,  # auto-picks most-negative f1
)
```

---

## 3. NPZ Archive Specification

The `results.npz` file is the primary scientific artifact. It MUST contain at minimum:

| Key | Shape | Description |
|-----|-------|-------------|
| `current_vectors` | `(n_solutions, n_basis)` | **Optimal population current vectors** (SH coefficients). Named explicitly for downstream reuse. |
| `pareto_objectives` | `(n_solutions, n_obj)` | Corresponding objective values. `n_obj` = 2 if `f3_as_constraint=True`, else 3 (legacy). |

> **Why `current_vectors` instead of `pareto_solutions`?** The former is unambiguous: these are the spherical-harmonic current coefficients that define the coil. Downstream studies (e.g., loading a vector for a follow-up single-vector simulation) should load this key.

Loading example:
```python
data = np.load("experiments/.../results.npz")
current_vectors = data["current_vectors"]      # (n_sol, n_basis)
objectives = data["pareto_objectives"]          # (n_sol, n_obj) — n_obj = 2 or 3
```

---

## 4. What Goes Where

### ✅ Project root (`tms_optimizer/`)
- `README.md`, `pyproject.toml`, `.gitignore`
- `src/` (source code only)
- `tests/` (regression tests only)
- `docs/` (long-form documentation)
- `.vscode/` (editor settings)

### ✅ `experiments/` or `outputs/` (experiment artifacts)
- Timestamped experiment directories
- All PNGs, JSONs, NPZs, logs
- **Never commit to git** — add to `.gitignore`

### ✅ `scripts/` or `demos/` (reusable scripts)
- Parameterized experiment scripts that accept `--output-dir`
- Not ad-hoc one-off notebooks

### ❌ Never in root
- `demo_result.json`
- `field_3d.png`
- `focus_areas.png`
- Any `.npz`, `.json`, `.txt` from a run

### ❌ Never in `tests/`
- Ad-hoc experiment scripts
- Visualization outputs
- Large data files

---

## 5. Experiment Script Templates

### 5.1 Standard 3-objective experiment (legacy baseline)

```python
#!/usr/bin/env python3
"""Template: 3-objective NSGA-II experiment."""
import argparse
import json
import time
from pathlib import Path
import numpy as np

from tms_optimizer.config.schemas import (
    ExperimentConfig, EllipseConfig, NSGA2Config,
    ObjectiveConfig, HardConstraintConfig,
)
from tms_optimizer.orchestration.experiment import run_experiment, save_experiment_results
from tms_optimizer.visualization.standard_plots import save_standard_plots


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--nsteps", type=int, default=7)
    parser.add_argument("--pop", type=int, default=100)
    parser.add_argument("--gen", type=int, default=100)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output-dir", type=str, required=True)
    args = parser.parse_args()

    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / "plots").mkdir(exist_ok=True)

    config = ExperimentConfig(
        coil_radius=0.09,
        head_radius=0.09,
        Nsteps=args.nsteps,
        ellipses=[EllipseConfig(center_theta=0.5, center_phi=0.0, a=0.15, b=0.08)],
        objective=ObjectiveConfig(
            f1_mode="mean",
            f2_mode="var",
            penalty_mode="threshold_linear",
            threshold_type="relative",
            side_lobe_threshold_ratio=0.50,
        ),
        nsga2=NSGA2Config(pop_size=args.pop, n_gen=args.gen, seed=args.seed),
    )

    with open(out / "config.json", "w") as f:
        json.dump(config.model_dump(), f, indent=2)

    t0 = time.perf_counter()
    result = run_experiment(config)
    elapsed = time.perf_counter() - t0

    save_experiment_results(result, str(out))
    print(f"Done. {len(result['pareto_solutions'])} solutions in {elapsed:.1f}s")


if __name__ == "__main__":
    main()
```

### 5.2 Recommended 2-objective CDP experiment (T-017 best practice)

```python
#!/usr/bin/env python3
"""Template: 2-obj CDP — current best practice (T-017 configuration)."""
import argparse, json, time
from pathlib import Path
import numpy as np

from tms_optimizer.config.schemas import (
    ExperimentConfig, EllipseConfig, NSGA2Config,
    ObjectiveConfig, HardConstraintConfig,
)
from tms_optimizer.orchestration.experiment import run_experiment, save_experiment_results
from tms_optimizer.visualization.standard_plots import save_standard_plots
from tms_optimizer.geometry.samplers import FibonacciSampler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--nsteps", type=int, default=25)
    parser.add_argument("--pop", type=int, default=200)
    parser.add_argument("--gen", type=int, default=500)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output-dir", type=str, required=True)
    args = parser.parse_args()

    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / "plots").mkdir(exist_ok=True)

    # 3-target standard configuration (~65° apart, phi in [-pi, pi])
    ellipses = [
        EllipseConfig(center_theta=0.0,  center_phi=0.0,      a=0.15, b=0.08, sampling_interval=0.05, alpha=1.5708),
        EllipseConfig(center_theta=0.628, center_phi=2.094,   a=0.15, b=0.08, sampling_interval=0.05, alpha=0.0),
        EllipseConfig(center_theta=0.785, center_phi=-2.244,  a=0.15, b=0.08, sampling_interval=0.05, alpha=0.0),
    ]

    config = ExperimentConfig(
        coil_radius=0.09,
        head_radius=0.09,
        Nsteps=args.nsteps,
        ellipses=ellipses,
        objective=ObjectiveConfig(
            f1_mode="min",                   # Ensure no under-stimulated target
            f2_mode="peak_correlation",       # Peak-centered + equal-peak
            peak_equalization_weight=5.0,
            peak_equalization_mode="cv_mean",
            penalty_mode="threshold_quadratic",  # Quadratic penalty for violating points
            threshold_type="absolute",       # Decoupled from E_m
            absolute_threshold=1e-4,
            f3_as_constraint=True,           # ← KEY: 2-objective mode
            f3_constraint_threshold=1e-4,
            constraint_handling="CDP",       # Constrained Dominance Principle
        ),
        nsga2=NSGA2Config(
            pop_size=args.pop, n_gen=args.gen, seed=args.seed,
            function_tolerance=1e-3,
            stall_gen_limit=50,
            constraint_tolerance=6e-4,
        ),
    )

    with open(out / "config.json", "w") as f:
        json.dump(config.model_dump(), f, indent=2)

    t0 = time.perf_counter()
    result = run_experiment(config)
    elapsed = time.perf_counter() - t0

    save_experiment_results(result, str(out))

    # Re-generate sampling points for visualization
    sampler = FibonacciSampler(n_total=max(1000, int(4 * np.pi / 0.05**2)))
    regions = [EllipseConfig(**e.model_dump()) for e in ellipses]
    target_points_cell, remaining_points = sampler.sample_regions(regions, 0.09)
    target_centers = np.array([[e.center_theta, e.center_phi] for e in ellipses])

    save_standard_plots(
        str(out), config=config, result=result,
        target_points_cell=target_points_cell,
        remaining_points=remaining_points,
        target_centers=target_centers,
        a_values=np.array([e.a for e in ellipses]),
        b_values=np.array([e.b for e in ellipses]),
        alpha_values=np.array([e.alpha for e in ellipses]),
    )

    print(f"Done. {len(result['pareto_solutions'])} solutions in {elapsed:.1f}s")
    # Quick metrics
    F = np.array(result["pareto_objectives"])
    if len(F) > 0:
        print(f"  f1 range: [{F[:,0].min():.4f}, {F[:,0].max():.4f}]")
        print(f"  f2 range: [{F[:,1].min():.4f}, {F[:,1].max():.4f}]")


if __name__ == "__main__":
    main()
```

Run it:
```bash
python scripts/run_experiment.py \
    --nsteps 25 --pop 200 --gen 500 \
    --output-dir experiments/2026-05-26_143052_T017_2obj_CDP_smoke
```

---

## 6. Evaluation Metrics Reference

### Target2Max (T2M)
- **Definition**: `T2M_i = max(E_target_i) / max(E_global)` for each target i
- **Interpretation**: Measures whether each target is among the strongest stimulation points globally.
- **Ideal value**: 1.0 (target peak equals global maximum)
- **Acceptable threshold**: T2M ≥ 0.95 means target is effectively the global peak
- **Usage**: Use as constraint when selecting best solution: `min(F[:,0])` subject to `all(T2M >= 0.95)`
- **Storage**: `metadata.json` → `target2max_per_solution` (list of lists)

### OA90 (Overstimulated Area at 90%)
- **Definition**: Area of non-target region where `E >= 0.9 * max(E_global)`, in cm²
- **Interpretation**: Measures "leakage" — how much healthy tissue is exposed to near-peak stimulation.
- **Ideal value**: 0 cm² (no overstimulation outside targets)
- **Typical range**: 0.2–12.3 cm² depending on configuration
- **Storage**: `metadata.json` → `oa90_per_solution` (list of dicts with `else_area_cm2`)

### FocusSum
- **Definition**: `Σ_i FWHM_area_i` across all targets, in cm²
- **Interpretation**: Lower = more focal (tighter spatial confinement). Primary figure of merit.
- **Typical values**: D3≈34.8, E3≈45.1, T-017(CDP)≈40.2
- **Trade-off**: Lower FocusSum often correlates with lower T2M (one target may be under-stimulated)

---

## 7. Reproducibility Checklist

Before treating an experiment as "done":

- [ ] `config.json` exists and matches the actual parameters used
- [ ] `metadata.json` records wall-clock time and random seed
- [ ] `results.npz` contains `current_vectors` and `pareto_objectives` (§3)
- [ ] `plots/` contains **all 7 figures** with the mandatory names (§2)
- [ ] All plots use the standardized module (`standard_plots.py`)
- [ ] Console log captured to `log.txt` (or at least `--save` used)
- [ ] Directory name includes key params + timestamp
- [ ] `.gitignore` excludes `experiments/` and `outputs/`
- [ ] **For CDP experiments**: verify `n_obj=2` in `pareto_objectives.shape[1]`
- [ ] **For CDP experiments**: check constraint violation rate is near 0% in metadata

---

## 8. Comparing Experiments

To compare two experiment runs, create a comparison script:

```python
# scripts/compare_experiments.py
import numpy as np
from pathlib import Path

exp_a = Path("experiments/2026-05-17_143052_nsteps7_pop100_gen100")
exp_b = Path("experiments/2026-05-17_150023_nsteps7_pop200_gen200")

for label, path in [("A", exp_a), ("B", exp_b)]:
    data = np.load(path / "results.npz")
    F = data["pareto_objectives"]
    X = data["current_vectors"]
    n_obj = F.shape[1]
    print(f"{label}: {len(F)} solutions, n_obj={n_obj}, f1 range [{F[:,0].min():.4f}, {F[:,0].max():.4f}]")
```

### Cross-experiment comparison outputs

When generating figures that compare **multiple experiments** (side-by-side Pareto fronts, field distributions, etc.), do NOT dump them into `experiments/` root. Instead:

```
experiments/
└── _comparisons/                    # Cross-experiment analysis artifacts
    ├── B2_vs_B1_gen500/
    │   ├── comparison_f1mean_vs_f1min.png
    │   └── comparison_bestf1_mean_vs_min.png
    ├── B2_pareto_three_representatives/
    │   ├── shared_scale.png
    │   └── individual_scale.png
    └── phase_B_summary/
        ├── table_focus_areas.md
        └── all_pareto_fronts.png
```

Rules for `_comparisons/`:
1. Use **descriptive directory names** (not timestamps) since these span multiple experiments
2. Include a `README.md` or `_summary.md` explaining what was compared and key findings
3. Comparison figures may deviate from the standard 7-figure template — use whatever layout best communicates the scientific point
4. The comparison directory is **NOT** an experiment directory — it contains no `config.json` or `results.npz`
5. **Never** place comparison PNGs directly in `experiments/` root or project root

---

## 9. Multi-Solution Combination Experiments (T-031 Series)

When a single Pareto solution is insufficient, the T-031 workflow explores linear combinations of Pareto solutions for better focality.

### Output conventions for combination experiments

Combination experiments produce **additional artifacts** beyond the standard 7 figures:

```
experiments/2026-05-24_1107_T031b_subset_selection/
├── config.json
├── results.npz                    # Combination coefficients + combined objectives
├── metadata.json
├── log.txt
├── plots/
│   ├── 01_target_regions.png
│   ├── 02_field_distribution.png      # Combined field from optimal linear combination
│   ├── 03_coil_winding.png            # Combined coil winding
│   ├── 04_focus_areas.png
│   ├── 05_pareto_front.png            # Coefficient-space Pareto front (if applicable)
│   ├── 06_target2max.png
│   ├── 07_oa90.png
│   └── 08_combination_coefficients.png # Bar chart of alpha coefficients (optional)
└── combination_report.json        # NEW: structured combination metadata
```

### combination_report.json schema
```json
{
  "parent_experiment": "experiments/2026-05-20_0046_T017_2obj_CDP_gen500/",
  "method": "LASSO" | "Greedy" | "OMP" | "NSGA-II_coeff",
  "n_parent_solutions": 76,
  "selected_indices": [3, 12, 45, ...],
  "coefficients": [0.35, -0.12, 0.58, ...],
  "combined_metrics": {
    "focus_sum": 34.18,
    "target2max_min": 0.998,
    "oa90_else_area_cm2": 0.15,
    "E_m": 0.000823
  },
  "improvement_vs_best_parent": {
    "focus_sum_pct": -15.2,
    "target2max_min_pct": +2.1
  }
}
```

---

## 10. Peak Equalization Weight Tuning Guide

The `peak_equalization_weight` controls how strongly NSGA-II forces target peaks to be equal.

| Weight | Behavior | Best for | Reference |
|--------|----------|----------|-----------|
| 1–5 | Weak equalization; correlation term dominates | Exploration, finding diverse Pareto front | E3 baseline (w=5) |
| 10 | Moderate equalization; good T2M balance | General use, T2M≥0.9 | T-006 |
| 20 | Strong equalization; may cause f2>0 degenerate solutions | Strict peak matching | T-018 (degenerate observed) |
| 50 | Very strong; convergence unstable | Not recommended | T-018 (unstable) |

**Recommendation**: Start with `weight=5` (E3 baseline). If T2M is insufficient (<0.9), increase to `weight=10`. Avoid >20.

---

## 11. Common Failure Modes & Troubleshooting

### "ModuleNotFoundError: No module named 'tms_optimizer'"
- **Cause**: Package not installed in editable mode.
- **Fix**: `pip install -e ".[dev,viz,opt]"` from project root.

### "ValueError: Nsteps=25 implies 675 basis functions; max 1000"
- **Cause**: Nsteps too large (validator rejects >1000 basis functions).
- **Fix**: Reduce Nsteps ≤ 30, or patch validator if you know what you're doing.

### "No Pareto solutions found" or empty `results.npz`
- **Cause 1**: `enable_hard_constraints=True` — feasible region vanishes.
  - **Fix**: Set `HardConstraintConfig(enable=False)`.
- **Cause 2**: `f3_as_constraint=True` with impossibly tight threshold.
  - **Fix**: Relax `f3_constraint_threshold` (e.g., 1e-3 instead of 1e-4).
- **Cause 3**: Generation count too low for population size.
  - **Fix**: Increase `n_gen` or reduce `pop_size`.

### Pareto front shows f2 > 0 in peak_correlation mode
- **Cause**: `peak_equalization_weight` too high (e.g., 20+).
- **Fix**: Reduce weight to 5–10. f2 should ideally be negative (correlation negative + small equalization term).

### OA90 or Target2Max missing from metadata
- **Cause**: Using old `compute_focus_areas` signature or outdated `run_experiment`.
- **Fix**: Ensure code version includes T-008 metrics integration. `run_experiment` result dict must contain `target2max_per_solution` and `oa90_per_solution`.

### `save_standard_plots` raises KeyError
- **Cause**: Missing required keys in `result` dict (e.g., `focus_areas_mean`).
- **Fix**: Ensure `run_experiment` completed successfully. For custom scripts, populate all result keys or pass `None` for optional plots.

### StochasticRanking import error
- **Cause**: `constraint_handling="StochasticRanking"` but `stochastic_ranking.py` missing.
- **Fix**: Verify file exists at `src/tms_optimizer/inverse/stochastic_ranking.py`. If missing, use `constraint_handling="CDP"` (always safe fallback).

---

## 12. Cleaning Up

```bash
# Remove old experiments (> 30 days)
find experiments/ -type d -mtime +30 -exec rm -rf {} +

# Or archive
 tar czf experiments_archive_2026-05.tar.gz experiments/
```

---

## 13. Quick Reference: Where to put what

| Artifact | Correct location | Wrong location |
|----------|-----------------|----------------|
| Experiment results | `experiments/YYYY-MM-DD_HHMMSS_params/` | Project root |
| Regression tests | `tests/test_*.py` | `scripts/` or root |
| Reusable scripts | `scripts/*.py` | Root or `tests/` |
| Visualization outputs | `experiments/.../plots/*.png` | Root |
| Config files | `experiments/.../config.json` | Root as `example_config.json` |
| Benchmark data | `../processtools/regression_benchmark/` | `src/` or `tests/` |
| Documentation | `README.md`, `docs/` | Scattered in root |
| Combination reports | `experiments/.../combination_report.json` | Root or `_comparisons/` |
