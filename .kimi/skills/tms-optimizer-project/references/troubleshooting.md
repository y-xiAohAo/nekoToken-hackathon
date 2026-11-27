# Troubleshooting Guide

## Environment Issues

### `ModuleNotFoundError: No module named 'tms_optimizer'`
**Cause**: Package not installed in editable mode.
**Fix**:
```bash
pip install -e ".[dev,viz,opt]"
```

### `ModuleNotFoundError: No module named 'pymoo'`
**Cause**: Optional dependency not installed.
**Fix**:
```bash
pip install -e ".[opt]"
# or full reinstall
pip install -e ".[dev,viz,opt]"
```

### Benchmark data missing
**Cause**: `benchmark_data_v1.mat` not found at `../processtools/regression_benchmark/`.
**Fix**: Verify the relative path from project root. Expected location:
```
D:/djh/search_agent/processtools/regression_benchmark/benchmark_data_v1.mat
```

---

## Experiment Failures

### `pymoo` version incompatibility
**Symptom**: NSGA-II crashes with attribute errors or API mismatch.
**Fix**: Lock pymoo to tested version:
```bash
pip install "pymoo>=0.6,<0.7"
```

### Experiment runs but produces no Pareto solutions
**Cause**: Constraint too tight → feasible region vanishes.
**Fix**: Use `f3_as_constraint=True` with CDP instead of hard constraints.

### `f2 > 0` appears in results
**Cause**: `peak_equalization_weight` too high (≥20).
**Fix**: Reduce weight to 5-15 range.

### Plots not generated
**Cause**: `matplotlib` backend issue or missing `plots/` directory.
**Fix**:
```python
from pathlib import Path
Path(output_dir / "plots").mkdir(exist_ok=True)
```

---

## Tool Call Failures (New Agent Sessions)

### Agent tries to use wrong working directory
**Symptom**: File not found errors for `index/` or `agents/`.
**Fix**: Ensure Kimi is launched from project root or a subdirectory within it. The skill discovery uses `.git` to find project root.

### Agent reads deprecated files
**Symptom**: Wastes tokens on AGENTS.md, CONTEXT.md, or MULTI_AGENT_FRAMEWORK.md.
**Fix**: Skill body explicitly lists "DO NOT READ" files. If agent still reads them, remind it to follow the startup checklist.

### Agent forgets to update indexes after task completion
**Symptom**: New experiments not visible to other agents.
**Fix**: All agent definitions have "完成后必做" section requiring index updates. If missed, human should update `index/TASK_INDEX.md` and `index/GLOBAL_INDEX.md`.

---

## Verification Commands

```bash
# Full test suite (should pass all)
pytest tests/ -q

# Specific validation tests
pytest tests/test_spherical_harmonics.py -v   # A-level vs MATLAB
pytest tests/test_constraints.py -v            # Constraints + NSGA2
pytest tests/test_orchestration.py -v          # End-to-end pipeline

# Smoke test a configuration
python scripts/run_experiment.py --nsteps 7 --pop 100 --gen 10 --output-dir experiments/smoke_test
```
