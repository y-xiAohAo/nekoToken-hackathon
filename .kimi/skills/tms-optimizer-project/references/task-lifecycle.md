# Task Lifecycle & Collaboration Flow

## Task State Machine

```
Pending → In Progress → Completed
   ↑         ↓
Blocked ←───┘
```

| State | Meaning | Who Can Set |
|-------|---------|-------------|
| **pending** | Waiting for an agent to pick up | Task Translator (creation) |
| **in_progress** | Agent is working on it | Agent (self-assignment) |
| **completed** | Done, results saved | Agent (self-reporting) |
| **blocked** | Dependency not satisfied | Agent (when inputs missing) |

## Standard Collaboration Flows

### Flow A: Experiment-Driven Chain
```
User proposes hypothesis
  → Task Translator creates T-XXX (experiment, pending)
  → Execution Agent reads T-XXX → runs experiment → marks completed
  → Execution Agent creates T-YYY (analysis, pending) with precise inputs
  → Analysis Agent reads T-YYY → analyzes → marks completed
  → Analysis Agent updates RESEARCH_LOG / creates literature task if needed
```

### Flow B: Literature-Driven Chain
```
Analysis Agent finds unexplained phenomenon
  → Creates T-XXX (literature, pending) with problem statement
  → Literature Scout reads T-XXX → searches → writes report → marks completed
  → Literature Scout creates T-YYY (experiment, pending) with method suggestion
  → Execution Agent runs experiment
```

## Index Update Responsibility

| File | Updated By | How |
|------|-----------|-----|
| `tasks/T-XXX.json` | Agent | Mark status, fill output_dir, result_summary, completed_at |
| `index/TASK_INDEX.md` | Human | Move task to Recently Completed, update status |
| `index/TASK_STATUS.md` | Human | Update status table |
| `index/GLOBAL_INDEX.md` | Human | Add new experiment/analysis/literature entries |

**Rule**: Agent writes "【建议更新索引】" section in their report; human performs the actual index updates.

## Exception Handling

| Scenario | Handling |
|----------|---------|
| Inputs file missing | Mark task blocked, report which path is missing |
| Code error during experiment | If config error → fix and retry; if bug → report and create analysis task; if architecture issue → escalate to human |
| Role conflict (user asks analyst to run code) | Refuse politely, offer 3 options: switch session, queue experiment task, or note as exception |
| No pending tasks for a role | Agent scans Recently Completed for un-analyzed experiments and proactively creates tasks |
