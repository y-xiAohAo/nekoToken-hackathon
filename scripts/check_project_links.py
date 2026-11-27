"""Check local Markdown links in the maintained project entry documents."""

from __future__ import annotations

import re
import sys
import argparse
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
ENTRY_FILES = (
    "README_先读这里.md",
    "AGENTS.md",
    "ARCHITECTURE.md",
    "PRELIMINARY_DESIGN_SPEC.md",
    "侦测定位_机制草案.md",
    "source_materials/story/README.md",
    "source_materials/story/当前故事主线_2042.md",
    "archive/README.md",
    "archive/story/README.md",
    "output/README.md",
    "output/imagegen/README.md",
    "output/预赛玩法框架_v0.4.md",
    "handoff/给参赛机Agent的首条消息.md",
)
LINK = re.compile(r"\]\(([^()\n]+)\)")


def main() -> int:
    """Exit nonzero when a maintained entry file points to a missing local path."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true", help="also inspect archived project Markdown")
    args = parser.parse_args()
    broken: list[str] = []
    checked = 0
    files = list(ENTRY_FILES)
    if args.all:
        files = sorted({*files, *(path.relative_to(ROOT).as_posix() for folder in ("archive", "output") for path in (ROOT / folder).rglob("*.md"))})
    for name in files:
        document = ROOT / name
        if not document.is_file():
            broken.append(f"missing document: {name}")
            continue
        for match in LINK.finditer(document.read_text(encoding="utf-8")):
            target = unquote(match.group(1).split("#", 1)[0])
            if not target or target.startswith(("https:", "http:", "mailto:", "data:", "//")):
                continue
            checked += 1
            resolved = (document.parent / target).resolve()
            if not resolved.is_relative_to(ROOT) or not resolved.exists():
                broken.append(f"{name}: {target}")
    print(f"Checked {checked} local links in {len(files)} project documents")
    for item in broken:
        print(item)
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
