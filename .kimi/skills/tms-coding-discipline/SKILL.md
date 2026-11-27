---
name: tms-coding-discipline
description: >
  TMS coil optimization project coding discipline and engineering quality enforcement.
  Auto-triggers when writing, modifying, or reviewing Python code in src/tms_optimizer/,
  scripts/, tests/, or pyproject.toml. Enforces: TDD (test before implementation),
  type annotations, specific exception handling, logging (no print), module docstrings,
  dependency tracking, and YAGNI.
---

# TMS Coding Discipline

## Hard Rules (Non-negotiable)

### 1. Test-Driven Development (TDD)
- **RED**: Write the failing test before any implementation.
- **GREEN**: Write the minimal code to make the test pass.
- **REFACTOR**: Clean up after the test passes.
- A new function or class MUST have a corresponding test file in `tests/`.
- Exception: `__init__.py`, re-export modules.

### 2. Type Annotations (Mandatory)
- Every function parameter and return value MUST have `typing` annotations.
- `Any` is forbidden unless justified in a docstring comment.
- Use `np.ndarray` with shape hints in docstrings when applicable.

### 3. Exception Handling
- Bare `except:` is **strictly forbidden**.
- Catch specific exceptions (`ValueError`, `FileNotFoundError`, etc.).
- Log with `logging.error()` including traceback and context.
- Re-raise or wrap with a project-specific exception if needed.

### 4. Logging (No Print)
- Use Python `logging` module. `print()` for status/progress is forbidden.
- Levels:
  - `DEBUG`: internal state, loop variables
  - `INFO`: user-visible progress, experiment milestones
  - `WARNING`: recoverable anomalies
  - `ERROR`: failures that break the current task

### 5. Module Docstring
- Every `.py` file MUST start with a module-level docstring describing purpose.

### 6. Dependency Hygiene
- New dependencies MUST be added to `pyproject.toml` under `[project.dependencies]` or `[project.optional-dependencies]`.
- Never install without updating `pyproject.toml`.

### 7. YAGNI & Minimal Changes
- Make the **smallest** change that satisfies the requirement.
- Do not refactor unrelated code.
- Do not add speculative features.

## Pre-commit Checklist

Before marking a task complete, verify:
- [ ] Tests exist and pass (`pytest tests/ -q`)
- [ ] Type annotations are complete (`mypy src/tms_optimizer/` if available)
- [ ] No bare `except:` blocks
- [ ] No `print()` statements (search with `grep -rn "print(" src/ scripts/`)
- [ ] Module docstrings present
- [ ] `pyproject.toml` updated if new deps added
- [ ] `AGENTS.md` / `SKILL.md` updated if conventions changed

## Code Review Gate

When reviewing code (your own or a subagent's), check in this order:
1. **Correctness**: Does it do what the task requires?
2. **Tests**: Are there tests? Do they cover edge cases?
3. **Types**: Are all public API functions fully annotated?
4. **Error Handling**: Are failure modes handled explicitly?
5. **Logging**: Is progress observable without `print()`?
6. **Dependencies**: Are new deps declared?

## Enforcement

This skill is paired with a `PreToolUse` hook (`.kimi/hooks/tms-coding-check.sh`) that:
- Blocks writes to `src/` without matching tests.
- Warns on `print()` usage in new files.
- Checks for bare `except:` in diffs.

Hook exit codes:
- `0` = allow
- `2` = block (stderr fed back to LLM as correction)
