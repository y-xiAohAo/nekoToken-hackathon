# Role Index (Pure Index)

> This file contains only summaries. For full role definitions, read the referenced files directly.

| Role | File | Core Responsibility | Trigger Condition |
|------|------|--------------------|--------------------|
| **Execution Agent** | `agents/execution_agent.md` | Modify code, configure params, run NSGA-II, save results | User wants to run experiments or change code |
| **Analysis Agent** | `agents/analysis_agent.md` | Read results, compute metrics, generate plots, write conclusions | User wants to analyze data or compare experiments |
| **Literature Scout** | `agents/literature_agent.md` | Literature search for specific bottlenecks, extract methodology | User wants literature support for an unexplained phenomenon |
| **Task Translator** | `agents/task_translator_agent.md` | Translate natural language requirements into `tasks/T-XXX.json` | User wants to create a new task or define requirements |

## Capability Boundaries (One-Line Summary)

- **Execution**: ✅ Code / Config / Run / Save ❌ Analyze / Literature / Decision
- **Analysis**: ✅ Metrics / Plots / Conclusions ❌ Run experiments / Code changes / Literature search
- **Literature**: ✅ Search / Extract / Recommend ❌ Run experiments / Analyze data / Write code
- **Task Translator**: ✅ Parse requirements / Generate task JSON ❌ Execute / Analyze / Search

## Standard Startup Reading Order

All roles share the same first 2 steps, then diverge:

```
1. index/GLOBAL_INDEX.md  (~1,500 tokens)
2. index/TASK_INDEX.md    (~600 tokens)
3. [Role-specific file]    (~1,700 tokens)
4. tasks/T-XXX.json        (~500 tokens,按需)
```

Total startup load: **~3,800 tokens** (constant regardless of project scale).
