"""Check maintained Markdown links using only the Python standard library."""

from __future__ import annotations

import argparse
import logging
import re
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
ENTRY_FILES = (
    "README.md", "CONTRIBUTING.md", "CHANGELOG.md", "README_先读这里.md",
    "AGENTS.md", "ARCHITECTURE.md", "PRELIMINARY_DESIGN_SPEC.md",
    "侦测定位_机制草案.md", "source_materials/story/README.md",
    "source_materials/story/当前故事主线_2042.md", "archive/README.md",
    "archive/story/README.md", "archive/production/README.md", "output/README.md",
    "output/imagegen/README.md", "output/预赛玩法框架_v0.4.md",
    "handoff/给参赛机Agent的首条消息.md",
)
LINK = re.compile(r"\]\(([^()\n]+)\)")
FENCE = re.compile(r"(?ms)^\s*```[^\n]*\n.*?^\s*```[^\n]*$")


def collect_documents(root: Path, include_archived: bool = False) -> list[Path]:
    """Include required entries and new development docs, not vendor manuals."""
    paths = {root / name for name in ENTRY_FILES}
    folders = ("docs", "game", "archive", "output") if include_archived else ("docs", "game")
    for folder in folders:
        paths.update(path for path in (root / folder).rglob("*.md")
                     if not {".godot", "node_modules"}.intersection(path.parts))
    return sorted(paths)


def check_links(root: Path, documents: list[Path]) -> list[str]:
    """Report missing or escaping local link targets, excluding fenced examples."""
    failures: list[str] = []
    root = root.resolve()
    for document in documents:
        document = document.resolve()
        label = document.relative_to(root).as_posix()
        if not document.is_file():
            failures.append(f"Missing document: {label}")
            continue
        content = FENCE.sub("", document.read_text(encoding="utf-8"))
        for match in LINK.finditer(content):
            target = unquote(match.group(1).strip("<>").split("#", 1)[0])
            if not target or target.startswith(("https:", "http:", "mailto:", "data:", "//")):
                continue
            resolved = (document.parent / target).resolve()
            if not resolved.is_relative_to(root) or not resolved.exists():
                failures.append(f"Broken local link in {label}: {target}")
    return failures


def main() -> int:
    """Expose the existing CLI, with optional historical document coverage."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="also check archived Markdown")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    try:
        documents = collect_documents(ROOT, args.all)
        failures = check_links(ROOT, documents)
    except (OSError, UnicodeError, ValueError):
        logging.exception("Unable to read project links")
        return 1
    for failure in failures:
        logging.error("%s", failure)
    logging.info("Checked %d documents; broken links or missing entries: %d", len(documents), len(failures))
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
