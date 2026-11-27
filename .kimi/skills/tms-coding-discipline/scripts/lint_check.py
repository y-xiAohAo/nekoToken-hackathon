#!/usr/bin/env python3
"""Automated lint checks for TMS coding discipline.

Runs checks on Python files before they are written/modified.
Can be invoked standalone or from the PreToolUse hook.
"""

import ast
import logging
import sys
from pathlib import Path

logger = logging.getLogger("tms.lint")


def check_type_annotations(tree: ast.Module) -> list[str]:
    """Check that all function definitions have type annotations."""
    errors = []
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef):
            if node.name.startswith("_") and not node.name.startswith("__"):
                continue  # private functions optional
            for arg in node.args.args:
                if arg.annotation is None:
                    errors.append(f"  Missing type annotation for parameter '{arg.arg}' in {node.name}()")
            if node.args.vararg and node.args.vararg.annotation is None:
                errors.append(f"  Missing type annotation for *{node.args.vararg.arg} in {node.name}()")
            if node.args.kwarg and node.args.kwarg.annotation is None:
                errors.append(f"  Missing type annotation for **{node.args.kwarg.arg} in {node.name}()")
            if node.returns is None:
                errors.append(f"  Missing return type annotation for {node.name}()")
    return errors


def check_bare_except(tree: ast.Module) -> list[str]:
    """Check for bare except: blocks."""
    errors = []
    for node in ast.walk(tree):
        if isinstance(node, ast.ExceptHandler) and node.type is None:
            errors.append(f"  Bare 'except:' found at line {node.lineno}")
    return errors


def check_print_usage(source: str, filepath: str) -> list[str]:
    """Check for print() statements."""
    errors = []
    tree = ast.parse(source)
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id == "print":
                errors.append(f"  print() found at line {node.lineno} in {filepath}")
    return errors


def check_module_docstring(tree: ast.Module, filepath: str) -> list[str]:
    """Check for module-level docstring."""
    errors = []
    if ast.get_docstring(tree) is None:
        errors.append(f"  Missing module-level docstring in {filepath}")
    return errors


def check_matching_test(filepath: Path) -> list[str]:
    """Check that src/ files have corresponding tests/."""
    errors = []
    rel = filepath.relative_to(filepath.anchor)
    parts = rel.parts
    if "src" in parts:
        basename = filepath.stem
        if basename in ("__init__", "conftest"):
            return errors
        test_name = f"test_{basename}.py"
        # Heuristic: look in tests/ directory at project root
        project_root = filepath
        for _ in range(len(parts) - parts.index("src") - 1):
            project_root = project_root.parent
        test_file = project_root / "tests" / test_name
        if not test_file.exists():
            errors.append(f"  Missing test file: tests/{test_name}")
    return errors


def lint_file(filepath: str) -> list[str]:
    """Run all checks on a single file."""
    path = Path(filepath)
    if not path.suffix == ".py":
        return []

    try:
        source = path.read_text(encoding="utf-8")
        tree = ast.parse(source)
    except SyntaxError as e:
        return [f"  Syntax error: {e}"]
    except Exception as e:
        return [f"  Could not read file: {e}"]

    errors = []
    errors.extend(check_module_docstring(tree, filepath))
    errors.extend(check_bare_except(tree))
    errors.extend(check_type_annotations(tree))
    errors.extend(check_print_usage(source, filepath))
    errors.extend(check_matching_test(path))
    return errors


def main():
    if len(sys.argv) < 2:
        print("Usage: lint_check.py <file1.py> [file2.py ...]", file=sys.stderr)
        sys.exit(1)

    all_errors = []
    for fp in sys.argv[1:]:
        errs = lint_file(fp)
        if errs:
            all_errors.append(f"{fp}:")
            all_errors.extend(errs)

    if all_errors:
        print("\n".join(all_errors), file=sys.stderr)
        sys.exit(2)
    else:
        print("All checks passed.")
        sys.exit(0)


if __name__ == "__main__":
    main()
