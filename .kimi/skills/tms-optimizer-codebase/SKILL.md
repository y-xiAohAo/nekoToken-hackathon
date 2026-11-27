---
name: tms-optimizer-codebase
description: Deep knowledge of the tms_optimizer project architecture, modules, APIs, MATLAB mappings, and common pitfalls. Use when reading, modifying, debugging, or extending the TMS coil optimization codebase.
skill_role: codebase
---

# TMS Optimizer — Codebase Reference

Project root: `D:\djh\search_agent\tms_optimizer`
Python package: `src/tms_optimizer`
Benchmark data: `../processtools/regression_benchmark/benchmark_data_v1.mat` (MATLAB R2024a, HDF5 v7.3)

---

## 1. Architecture (layered view)

```
src/tms_optimizer/
├── config/schemas.py              # Pydantic models: ExperimentConfig, ObjectiveConfig, ProblemConfig, PluginInstance, ModifierConfig, NSGA2Config
├── core/                          # Pure math (no external deps)
│   ├── spherical_harmonics.py     # assoc_legendre, Y_lm (complex/real/vector)
│   └── vector_magnitude.py        # |V| for [V_theta, V_phi]
├── physics/                       # Physical quantities
│   ├── basis_field.py             # electric_field_basis, current_basis, streamfunction_basis (frozen)
│   ├── energy.py                  # magnetic_energy_hessian, magnetic_energy
│   └── reference_coils.py         # figure-of-eight SH coefficients / energy / field (literature packet B)
├── geometry/                      # Sampling & regions
│   ├── regions.py                 # EllipticalRegion, SphericalCapRegion, angular_distance_and_azimuth
│   └── samplers.py                # FibonacciSampler, fibonacci_spiral
├── forward/                       # Forward problem
│   ├── field_computer.py          # compute_region_efield (pre-compute basis responses)
│   └── field_assembler.py         # assemble_electric_field, assemble_streamfunction
├── inverse/                       # Inverse problem (optimization)
│   ├── constraints/direction.py   # generate_directional_constraints (A_ineq, A_eq)
│   ├── nsga2_optimizer.py         # TMSProblem, run_nsga2 (pymoo NSGA-II) — thin wrappers over plugin problem
│   ├── stochastic_ranking.py      # StochasticRankingSurvival (Runarsson & Yao 2000)
│   ├── convex_solver.py           # Koponen-2015 min-energy convex QP/SOCP reference (literature packet E)
│   ├── plugins/                   # Plugin protocols and built-in implementations
│   │   ├── base.py                # ObjectivePlugin, ConstraintPlugin, ModifierPlugin protocols
│   │   ├── registry.py            # @register_objective / constraint / modifier decorators + loaders
│   │   ├── objectives.py          # target_field_strength, uniformity, off_target, gap, regularization, magnetic_energy
│   │   ├── constraints.py         # off_target, current_density, hard, directional, target_field_equality
│   │   └── modifiers.py           # regularization modifier
│   └── problem/                   # Plugin assembly
│       ├── context.py             # SharedContext + EvaluationContext
│       ├── builder.py             # build_problem(): config → TMSProblem
│       └── tms_problem.py         # pymoo Problem shell delegating to plugins
├── objectives/
│   └── penalties.py               # evaluate_combined_fields, constraint_violation_mask (legacy helpers)
├── metrics/
│   └── focality.py                # compute_focus_areas (FWHM, Target2Max, OA90)
├── manufacturability/             # T-060: Manufacturing complexity metrics (post-processing)
│   ├── __init__.py                # Public API: CoilComplexityInput / WindingMetricsInput + compute_all
│   ├── _types.py                  # CoilComplexityInput + DEFAULT_NTHETA/DEFAULT_NPHI
│   ├── compute_all.py             # compute_all(): unified metric entry
│   ├── current_density.py         # P0: |∇Ψ| peak/mean/histogram (200×400 internal grid)
│   ├── energy_spectrum.py         # P1: SH energy spectrum E(l) = Σ_m |a_lm|² (pure coefficient)
│   ├── smoothness.py              # P1: smoothness Path A (analytical) + Path B (numerical)
│   ├── turns.py                   # P1: estimated turns (Ψ_max − Ψ_min) / I_wire
│   ├── winding_metrics.py         # B-layer discrete-winding metrics (turn_count, wire length, spacing…)
│   └── manufacturability_check.py # hard-criteria check (evaluate_manufacturability)
├── data_export/                   # T-040: Pure-data mesh generation (decoupled from matplotlib)
│   └── __init__.py                # get_field_distribution_data, get_coil_winding_data, get_target_regions_data
├── api/                           # T-041: FastAPI backend (REST + SSE + SQLite)
│   ├── main.py
│   ├── routers/experiments.py
│   ├── services/runner.py
│   └── models/db.py
├── visualization/                 # Matplotlib plots
│   ├── spherical_plots.py         # plot_electric_field_magnitude
│   ├── contour_plots.py           # plot_spherical_contour (bipolar colormap)
│   ├── region_plots.py            # visualize_regions_3d, plot_ellipse_boundary
│   ├── standard_plots.py          # save_standard_plots (standard experiment figures)
│   └── literature_comparison.py   # Koponen-2015 comparison plots (literature packet F)
├── orchestration/
│   └── experiment.py              # run_experiment (end-to-end pipeline)
└── cli.py                         # CLI entry point

frontend/                          # T-042: React SPA (Vite + Three.js + Recharts)
├── src/                           # Pages, components, API client
├── e2e/                           # Playwright end-to-end tests
└── dist/                          # Production build output
```
> Docker 编排在仓库根：`Dockerfile.backend` + `docker-compose.yml`。

---

## 2. Key Data Structures

### Coordinate conventions
- Points: `[r, theta, phi]` where `theta` = polar angle (0=north pole, π=south pole), `phi` = azimuthal (0~2π)
- Vector fields: last axis = `[theta_component, phi_component]`
- Basis fields: `(n_basis, n_points, 2)` — pre-computed for all (l,m) pairs

### Nsteps → n_basis
```python
n_basis = sum(2*l + 1 for l in range(1, Nsteps+1))  # = Nsteps*(Nsteps+2)
# Nsteps=2 → 8, Nsteps=7 → 63, Nsteps=15 → 255, Nsteps=25 → 675
```

### ExperimentConfig / ObjectiveConfig / HardConstraintConfig / ProblemConfig

> **Full field definitions are in `docs/api-reference.md`** (mutable, updated with code changes).
> This skill only retains stable structural knowledge.

Key stable facts:
- `Nsteps` controls SH truncation order; validator caps at 1000 basis functions
- `n_basis = Nsteps * (Nsteps + 2)`
- `objective` field contains all f1/f2/f3 mode knobs (legacy; see docs for exhaustive list)
- `hard_constraint` enables optional hard inequalities (legacy; usually disabled — feasible region vanishes)
- **Plugin-first config**: `ExperimentConfig.problem: ProblemConfig` supersedes `objective` / `hard_constraint`
  - `ProblemConfig.objectives`: list of `PluginInstance(plugin, name, args)` — minimized by NSGA-II
  - `ProblemConfig.constraints`: list of `PluginInstance` — `g <= 0` feasible
  - `ProblemConfig.modifiers`: list of `ModifierConfig(plugin, target, args)` — additive penalty to an objective or constraint
  - `ProblemConfig.constraint_handling`: `"CDP"` (default) or `"StochasticRanking"`
- Backward compatibility: `ObjectiveConfig` / `HardConstraintConfig` / `ManufacturabilityConfig` are automatically translated to `ProblemConfig` via `ExperimentConfig.to_problem_config()`

---

## 3. MATLAB ↔ Python Mapping

| Python module | MATLAB source | Validation |
|---------------|--------------|------------|
| `core/spherical_harmonics.py` | `LegendrePlm.m`, `SphericalHarmonicY.m`, `RealSphericalHarmonicY.m`, `SphericalHarmonicVectorY.m` | **A-level** RMSE < 1e-12 |
| `physics/basis_field.py` | `SphericalHarmonicE_lm.m`, `SphericalHarmonicI_lm.m`, `streamfunctionI_lm.m` | **A-level** RMSE < 1e-10 |
| `physics/energy.py` | `GenHessianofEnergy.m`, `CalcuBfieldEnergy.m` | **A-level** |
| `forward/field_computer.py` | `CalcuRegionEfield.m` | **A-level** |
| `forward/field_assembler.py` | `CombineBasisE.m`, `CombineBasisI.m` | **A-level** |
| `inverse/constraints/direction.py` | `GenDirectionalConstraintMatrix.m` | **A-level** RMSE < 1e-8 |
| `objectives/penalties.py` | `BeyondConstraint.m` | **A-level** RMSE < 1e-10 |
| `inverse/nsga2_optimizer.py` | `NSGAOpt.m`, `delta_based_weights.m` | **B-level** (stochastic algorithm) |
| `inverse/stochastic_ranking.py` | — | **B-level** (alternative constraint handling) |
| `geometry/samplers.py` | `multi_ellipse_sampling_meshed.m`, `robust_spiral` | **B-level** (RNG differs) |
| `visualization/spherical_plots.py` | `plot_spherical_e_field_mesh.m` | Smoke test |
| `visualization/contour_plots.py` | `plot_spherical_contour.m` | Smoke test |
| `visualization/region_plots.py` | `visualize_multi_ellipses.m` | Smoke test |

> **A-level** = bit-exact or RMSE < 1e-10 against `benchmark_data_v1.mat`.
> **B-level** = algorithmic/statistical equivalence only.

---

## 4. Objective-Function Reference

### f1_mode: target-field strength
| Mode | Formula |
|------|---------|
| `mean` | f1 = -mean(E_target) |
| `min` | f1 = -min(E_target) |
| `sum` | f1 = -sum(E_target) |

> **Current recommendations** (which mode to choose): see `docs/experiment-patterns.md` §2

### f2_mode: uniformity / peak equalization
| Mode | Formula |
|------|---------|
| `var` | f2 = var(E_target) |
| `std` | f2 = std(E_target) |
| `cv` | f2 = std / mean |
| `per_region_var` | f2 = Σ var(region_i) |
| `peak_correlation` | f2 = corr_term + w * eq_term |

**peak_correlation structure** (stable):
- `corr_term`: mean correlation between E and distance from target center
- `eq_term`: peak equalization penalty (cv_mean / cv_min / peak_ratio)
- `peak_equalization_weight`: scalar weight

> **Tuning guidance**: see `docs/experiment-patterns.md` §4

### f3: off-target penalty / constraint
| penalty_mode | Description |
|--------------|-------------|
| `threshold_linear` | Σ(E_else - threshold) for violating points |
| `threshold_quadratic` | Σ(E_else - threshold)² for violating points |
| `off_target_energy` | Σ(E_else²) |
| `gap_energy` | Σ(E_gap²) for inter-target corridor points |

**threshold_type**:
- `relative`: threshold = E_m * ratio (couples f1↔f3)
- `absolute`: threshold = constant (decoupled)

**f3_as_constraint mode**:
- When `True`, f3 becomes inequality constraint; NSGA-II switches to 2-objective
- Constraint handling: `CDP` (default) or `StochasticRanking`

> **Architecture evolution and current best practice**: see `docs/experiment-patterns.md` §2-3

---

## 5. Known Pitfalls

### 5.1 MATLAB HDF5 quirks (benchmark_data_v1.mat)
1. **Arrays transposed**: MATLAB saves `(M,N,K)` as `(K,N,M)`. Fix: `np.transpose(arr, (2,1,0))`.
2. **Cell arrays as object refs**: Dereference with `f[ref][:]`.
3. **2D points**: `N×3` saved as `3×N`. Fix: transpose when `shape[0]==3 and shape[1]!=3`.
4. **Complex numbers**: Stored as compound dtype `[('real','<f8'),('imag','<f8')]`. Fix: `real + 1j*imag`.

### 5.2 Coefficient scale
- QP benchmark coefficients are **tiny**: `[-0.016, 0.047]`.
- NSGA2 search bounds are `[-current_bound, +current_bound]`; `ObjectiveConfig.current_bound` default is `100_000`（陷阱详见 optimization-spec.md §7-2）.
- Physical E-field at r=0.09m is **millivolt-level** for moderate coefficients.
- Do NOT confuse coefficient magnitude with E-field magnitude.

### 5.3 Constraint architecture evolution
- **Legacy**: f3 as 3rd objective + relative threshold → f1↔f3 coupling loop
- **Transitional**: f3 as inequality constraint (2-objective via CDP or StochasticRanking)
- **Current plugin system**: `ProblemConfig` declaratively assembles `ObjectivePlugin`, `ConstraintPlugin`, and `ModifierPlugin` instances. Built-in plugins cover all legacy modes.
- **Hard constraints** (`HardConstraintConfig.enable=True`): ~3000+ inequalities. Feasible region often vanishes — **do NOT enable for exploration**.

> **Detailed evolution history and current best practice**: see `docs/experiment-patterns.md` §2-3 and `docs/api-reference.md` §Plugin System.

### 5.6 Plugin registry rules
- New plugins must be decorated with `@register_objective(name)`, `@register_constraint(name)`, or `@register_modifier(name)`.
- Duplicate names raise `ValueError`; `load_builtin_plugins()` is idempotent.
- Plugins must implement `__call__(self, ctx: EvaluationContext) -> float` and accept plugin-specific args in `__init__`.
- `ModifierConfig.args` uses `lambda_` for regularization strength because `lambda` is a Python keyword; legacy `regularization_lambda` is mapped automatically.

### 5.4 Focal area and evaluation metrics
- `compute_focus_areas` returns dict with: `focus_areas`, `target2max`, `oa90`
- Two threshold modes: `threshold_ratio` (FWHM, relative) and `abs_threshold` (fixed, decoupled)

### 5.5 f1_mode ↔ f2_mode compatibility
> **Compatibility matrix and configuration recommendations**: see `docs/experiment-patterns.md` §3

---

## 6. Common API Snippets

### Run full experiment (minimal example)
```python
from tms_optimizer.config.schemas import ExperimentConfig, EllipseConfig, NSGA2Config, ObjectiveConfig
from tms_optimizer.orchestration.experiment import run_experiment

config = ExperimentConfig(
    coil_radius=0.09, head_radius=0.09, Nsteps=25,
    ellipses=[EllipseConfig(...)],
    objective=ObjectiveConfig(...),  # see docs/api-reference.md for full fields
    nsga2=NSGA2Config(pop_size=200, n_gen=500, seed=42),
)
result = run_experiment(config)
# result keys: config, n_basis, pareto_solutions, pareto_objectives,
#   focus_areas_per_solution, focus_areas_mean,
#   target2max_per_solution, oa90_per_solution, execution_time_sec
```

> **Full configuration with current best-practice values**: see `docs/experiment-patterns.md`

### Compute focal area manually (updated signature)
```python
from tms_optimizer.metrics.focality import compute_focus_areas
focus = compute_focus_areas(
    coeffs=coeffs,
    EfieldTargetTCell=E_target_cell,
    EfieldElseRegion=E_else,
    target_points_cell=target_points_cell,
    remaining_points=remaining_points,
    ellipse_centers=target_centers,
    threshold_ratio=0.5,  # or abs_threshold=1e-4
)
# Returns dict: focus_areas, target2max, oa90
```

### Evaluate combined fields
```python
from tms_optimizer.objectives.penalties import evaluate_combined_fields
E_magT, E_magElse = evaluate_combined_fields(coeffs, EfieldTargetT, EfieldElseRegion)
```

### Evaluate manufacturability complexity (T-060d)
```python
from tms_optimizer.manufacturability import (
    CoilComplexityInput,
    max_current_density,
    mean_current_density,
    sh_energy_spectrum,
    streamfunction_smoothness_path_b,
    estimated_turns,
)

# Input is sampling-agnostic: only coefficients + geometry needed
inp = CoilComplexityInput(
    coefficients=coeffs,           # a_lm from NSGA-II solution
    lm_pairs=lm_pairs,             # (l, m) list aligned with coefficients
    sphere_radius=0.09,            # R in metres
    I_wire=1000.0,                 # assumed wire current (A), default 1kA
)

# Batch 1 (P0) — spatial metrics, ~0.5-2s per solution
k_max = max_current_density(inp)           # |∇Ψ|_max
k_mean = mean_current_density(inp)         # <|∇Ψ|>

# Batch 2 (P1) — energy spectrum (pure coefficient, instant)
spectrum = sh_energy_spectrum(inp)         # dict[l] = Σ_m |a_lm|²

# Batch 2 (P1) — smoothness path B (numerical integral)
smooth_b = streamfunction_smoothness_path_b(inp)  # ∫|∇Ψ|² dS

# Batch 2 (P1) — estimated turns (grid-based extremum search)
turns = estimated_turns(inp)               # (Ψ_max − Ψ_min) / I_wire
```

**Design notes**:
- The module is **sampling-agnostic**: it generates its own regular grid internally.
- Default grid is 200×400 for accuracy (<5% error on peak gradient).
- A 层指标（current density / energy spectrum / smoothness Path A+B / estimated turns）经 `CoilComplexityInput`；B 层绕组指标（winding_metrics.py）经 `WindingMetricsInput`；统一入口 `compute_all()`；硬判据 `evaluate_manufacturability()`。详见 `CODEMAP.md` §2.8。
- `self_intersection_count` 容差（默认 0.1 mm）为经验值，待视觉校准。
- **No analytical maximum** for multi-mode superposition; numerical grid scan is the standard approach in literature (Rissanen 2023, bfieldtools).

---

## 7. Tests

```bash
cd tms_optimizer
pytest tests/ -q          # 411 tests collected (2026-09-03), all should pass
pytest tests/test_spherical_harmonics.py -v   # A-level validation
pytest tests/test_constraints.py -v            # A-level constraints + legacy NSGA2 objectives
pytest tests/test_nsga2_optimizer.py -v        # modular plugin system equivalence tests
```

Test files:
- `test_spherical_harmonics.py` — A-level vs benchmark_data_v1.mat
- `test_forward.py` — field computation
- `test_constraints.py` — directional constraints + legacy NSGA2 objectives
- `test_nsga2_optimizer.py` — plugin registry, config translation, and legacy-vs-modular equivalence
- `test_geometry.py` — region contains, Fibonacci spiral
- `test_visualization.py` — smoke tests for plots
- `test_config.py` — Pydantic validation (legacy + ProblemConfig)
- `test_orchestration.py` — end-to-end pipeline
- `test_metrics.py` — focal area computation + Target2Max + OA90
- `test_manufacturability.py` — current density metrics (invariant + symmetry tests)
- `test_cli.py` — CLI argument parsing

---

## 8. Dependencies

Core: `numpy`, `scipy`, `h5py`, `pydantic`, `cvxpy` (cvxpy 在核心 dependencies；见 pyproject.toml)
Optimization: `pymoo`, `scikit-learn`
Visualization: `matplotlib`
API (optional): `fastapi`, `uvicorn`, `sqlalchemy`, `aiosqlite`
Testing: `pytest`, `pytest-cov`
Frontend: `react`, `vite`, `three.js`, `recharts`, `@react-three/fiber`

Install backend: `pip install -e ".[dev,viz,opt,api]"`
Install frontend: `cd frontend && npm install`
