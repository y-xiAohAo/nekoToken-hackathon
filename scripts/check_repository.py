"""Validate Git content and documentation without Godot, model keys or bundled tools."""

from __future__ import annotations

import logging
import re
import subprocess
from pathlib import Path, PureWindowsPath

from check_project_links import ROOT, check_links, collect_documents

MAX_BYTES = 50 * 1024 * 1024
LOCAL_ROOTS = {"tmp", "tools", "build", "exports"}
CACHE_PARTS = {".git", ".godot", ".venv", "__pycache__", "node_modules", ".pytest_cache", ".mypy_cache", ".ruff_cache"}
TEXT_SUFFIXES = {".md", ".txt", ".json", ".jsonl", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".ps1", ".py", ".js", ".ts", ".html", ".gd", ".tscn", ".tres", ".example"}
SECRET = re.compile(
    r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-[A-Za-z0-9_-]{24,})\b"
    r"|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----"
)


def tracked_paths(root: Path) -> list[Path]:
    """Check the index plus new non-ignored files, including accidentally tracked caches."""
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        capture_output=True, check=True, timeout=30,
    )
    return sorted({Path(name) for name in result.stdout.decode("utf-8").split("\0") if name})


def validate_paths(root: Path, paths: list[Path], max_bytes: int = MAX_BYTES) -> list[str]:
    """Reject local-only content, missing files, oversized blobs and recognizable secrets."""
    failures: list[str] = []
    root = root.resolve()
    for relative in paths:
        label = relative.as_posix()
        path = (root / relative).resolve()
        if relative.is_absolute() or PureWindowsPath(label).is_absolute() or not path.is_relative_to(root):
            failures.append(f"Path outside repository: {label}")
            continue
        if not path.is_file():
            failures.append(f"Missing file (stage intentional deletions): {label}")
            continue
        private_env = relative.name.startswith(".env") and relative.name != ".env.example"
        if (relative.parts[0] in LOCAL_ROOTS or CACHE_PARTS.intersection(relative.parts)
                or private_env or relative.suffix.lower() in {".pfx", ".p12", ".keystore", ".pyc"}):
            failures.append(f"Local-only or credential file in Git candidates: {label}")
            continue
        if path.stat().st_size > max_bytes:
            failures.append(f"File exceeds {max_bytes} bytes; choose LFS or release storage: {label}")
            continue
        if relative.suffix.lower() in TEXT_SUFFIXES:
            content = path.read_text(encoding="utf-8", errors="replace")
            if SECRET.search(content):
                failures.append(f"Possible embedded credential (value hidden): {label}")
    return failures


def main() -> int:
    """Run portable checks and return a failing status for actionable repository defects."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    try:
        paths = tracked_paths(ROOT)
        failures = validate_paths(ROOT, paths)
        documents = collect_documents(ROOT)
        failures.extend(check_links(ROOT, documents))
    except (OSError, UnicodeError, ValueError, subprocess.SubprocessError):
        logging.exception("Repository check could not complete")
        return 1
    for failure in failures:
        logging.error("%s", failure)
    logging.info("Repository: %d files, %d maintained documents, %d issues", len(paths), len(documents), len(failures))
    logging.info("Scope: repository hygiene only; Godot gameplay and model services are not tested here.")
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
