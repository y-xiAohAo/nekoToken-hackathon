"""Rebase local Markdown links after moving superseded story materials."""

from __future__ import annotations

import os
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LINK = re.compile(r"\]\(([^()\n]+)\)")


def moved_paths() -> dict[Path, Path]:
    """Return original-to-archive paths for this worldbuilding cleanup."""
    pairs: dict[Path, Path] = {}
    story_groups = {
        "legacy_请本人到场": ["背景故事素材.docx", "请本人到场_原文提取.md"],
        "superseded_2026": ["游戏背景——2026.docx"],
        "superseded_2042": ["游戏背景v1.docx", "游戏背景v1(1).docx"],
        "reconciliation": ["故事线对照_2026片段.md"],
    }
    for group, names in story_groups.items():
        for name in names:
            pairs[ROOT / "source_materials/story" / name] = ROOT / "archive/story" / group / name
    for name in (
        "AI_PLAY_72H_预赛方案_精炼特色版_v0.8.md",
        "AI_PLAY_72H_预赛方案_精炼特色版_v0.8.pdf",
        "AI_PLAY_72H_预赛方案_2042故事线版_v0.9.md",
    ):
        pairs[ROOT / "output/pdf" / name] = ROOT / "output/archive/submissions" / name
    visual_dir = ROOT / "output/archive/visuals/legacy_请本人到场"
    for path in visual_dir.iterdir():
        if path.is_file():
            pairs[ROOT / "output/imagegen" / path.name] = path
    return pairs


def markdown_files() -> list[Path]:
    """List project materials without touching vendored skills or runtime files."""
    result = list(ROOT.glob("*.md"))
    for folder in ("archive", "output", "source_materials/story", "handoff"):
        result.extend((ROOT / folder).rglob("*.md"))
    return result


def main() -> None:
    """Keep link targets intact while retaining each moved original's text."""
    moves = moved_paths()
    inverse = {new: old for old, new in moves.items()}
    edited = 0
    rebased = 0
    for document in markdown_files():
        original_document = inverse.get(document, document)
        original_text = document.read_text(encoding="utf-8")

        def replace(match: re.Match[str]) -> str:
            nonlocal rebased
            raw = match.group(1)
            path_text, sep, fragment = raw.partition("#")
            if not path_text or path_text.startswith(("http:", "https:", "mailto:", "data:", "//", "/")):
                return match.group(0)
            current_target = (document.parent / path_text).resolve()
            if current_target.exists():
                return match.group(0)
            original_target = (original_document.parent / path_text).resolve()
            destination = moves.get(original_target, original_target)
            if not destination.exists():
                return match.group(0)
            relative = Path(os.path.relpath(destination, document.parent)).as_posix()
            rebased += 1
            return "](" + relative + (sep + fragment if sep else "") + ")"

        new_text = LINK.sub(replace, original_text)
        if new_text != original_text:
            document.write_text(new_text, encoding="utf-8")
            edited += 1
    print(f"Rebased {rebased} links in {edited} Markdown files")


if __name__ == "__main__":
    main()
