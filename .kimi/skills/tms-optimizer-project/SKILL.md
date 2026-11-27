---
name: tms-optimizer-project
description: >
  TMS coil optimization project context loader and role router.
  Use when starting ANY session in the tms_optimizer project located at
  D:\djh\search_agent\tms_optimizer.
  Triggers on: requests involving TMS, NSGA-II, coil optimization, multi-target
  focality, spherical harmonics, streamfunction, Pareto optimization, experiment
  execution, data analysis, literature review, task management, or any work within
  this project directory. Automatically guides index file loading and agent role
  selection.
skill_role: project-context
---

# TMS Optimizer — Project Context

Project root: `D:\djh\search_agent\tms_optimizer`

---

## 1. New Session Startup Checklist

Every agent session in this project **must** follow this exact order:

```
1. Read index/GLOBAL_INDEX.md
   → Build the "map": know where all resources are
   → Read only the first section (~800 words); detailed tables are for later lookup

2. Read index/TASK_INDEX.md
   → Find pending tasks matching your role type
   → Note the task ID(s) you need to process

3. Read agents/<role>_agent.md
   → Load your full role definition and capability boundaries
   → execution → agents/execution_agent.md
   → analysis  → agents/analysis_agent.md
   → literature → agents/literature_agent.md
   → task translation → agents/task_translator_agent.md

4. Read tasks/T-XXX.json for your pending task(s)
   → Get inputs, expected_outputs, dependencies

5. Execute task → Update tasks/T-XXX.json and index files
```

**Prohibited**: Starting work without reading the index files first.

---

## 2. Role Router

Determine which agent role to load based on user intent:

| User Intent | Role | Read |
|------------|------|------|
| "Run experiment / change code / verify config" | Execution Agent | `agents/execution_agent.md` |
| "Analyze results / compare experiments / plot" | Analysis Agent | `agents/analysis_agent.md` |
| "Search literature / review papers / methodology" | Literature Scout | `agents/literature_agent.md` |
| "Create task / translate requirement / plan" | Task Translator | `agents/task_translator_agent.md` |

If the user does not specify a role, infer from the pending task type in `index/TASK_INDEX.md`.

---

## 3. Environment Verification

Before running any experiment, verify the environment:

```bash
# Verify all tests pass
pytest tests/ -q

# Verify benchmark data is accessible
ls ../processtools/regression_benchmark/benchmark_data_v1.mat

# Install dependencies if needed
pip install -e ".[dev,viz,opt]"
```

---

## 4. Knowledge Layers (Stable → Mutable)

This project separates **stable knowledge** (skills) from **mutable state** (project files):

| Layer | Location | Update Frequency | Content |
|-------|----------|-----------------|---------|
| **Skills** (stable) | `.kimi/skills/` | Rarely | Structural knowledge: architecture, workflows, physics background |
| **Project files** (mutable) | `docs/`, `index/` | Frequently | Current API fields, best configs, experiment conclusions |

### Project-level skills (auto-discovered from `.kimi/skills/`)

| Skill | Trigger | Content |
|-------|---------|---------|
| `tms-optimizer-project` (this file) | Any work in this project | Startup checklist, role routing, index loading strategy |
| `tms-optimizer-codebase` | Reading / modifying / debugging code | Architecture (10 layers), coordinate conventions, MATLAB mappings, tests |
| `tms-optimizer-experiment` | Running experiments / generating outputs | Directory structure, visualization standards, NPZ spec, reproducibility |
| `tms-research-assistant` | Designing experiments / interpreting results | TMS physics background, literature map, objective-function methodology |

### Mutable reference files (load when needed)

| File | Load When |
|------|-----------|
| `references/roles.md` | Quick summary of all 4 roles |
| `agents/task_translator_agent.md` | Creating tasks or translating requirements |
| `references/troubleshooting.md` | Encountering errors |
| `docs/api-reference.md` | **Modifying code / running the web stack** — full API fields, FastAPI endpoints, React frontend routes, startup commands, test matrix |
| `docs/experiment-patterns.md` | **Designing experiments** — current best configs, parameter tuning |
| `index/GLOBAL_INDEX.md` | **Any session start** — resource map, known conclusions, open questions |

---

## 5. Project Architecture at a Glance

```
tms_optimizer/
├── src/tms_optimizer/          # Source code (11 layers)
│   ├── core/                    # Pure math
│   ├── physics/                 # Physical quantities
│   ├── geometry/                # Sampling & regions
│   ├── forward/                 # Forward problem
│   ├── inverse/                 # Optimization (NSGA-II)
│   ├── objectives/              # Penalty functions
│   ├── metrics/                 # Focality evaluation
│   ├── data_export/             # T-040: JSON-serializable mesh data
│   ├── api/                     # T-041: FastAPI backend
│   ├── visualization/           # Matplotlib plots
│   └── orchestration/           # End-to-end pipeline
├── frontend/                    # T-042: React SPA (Vite + Three.js)
├── tests/                       # Regression tests (pytest + vitest + playwright)
├── experiments/                 # Experiment artifacts (timestamped dirs)
├── experiments/_comparisons/    # Cross-experiment analysis outputs
├── tasks/                       # Task definitions (T-XXX.json)
├── index/                       # Indexes (Agent "memory")
│   ├── GLOBAL_INDEX.md          # Resource map (MUST read on startup)
│   ├── TASK_INDEX.md            # Task directory (MUST read on startup)
│   └── TASK_STATUS.md           # Status snapshot (CAN read on startup)
├── agents/                      # Full role definitions
└── agents/reports/              # Literature & analysis reports
```

---

## 6. Key Constraints

- **One experiment = one directory** under `experiments/YYYY-MM-DD_HHMMSS_params/`
- **Never dump outputs** (PNG, JSON, NPZ) into the project root
- **Always use `standard_plots`** for visualization consistency
- **Update indexes after completion**: Agent updates `tasks/T-XXX.json`; human updates `index/GLOBAL_INDEX.md` and `index/TASK_INDEX.md`
