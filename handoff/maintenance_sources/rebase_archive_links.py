"""Update local Markdown links after the 2026-11-26 archive move."""

from __future__ import annotations

import posixpath
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ROOT_CONCEPTS = (
    "AGENT_NECESSITY_RESEARCH.md",
    "CONCRETE_GAME_LOOP_CANDIDATE.md",
    "CONTRACT_ROOM_CANDIDATE.md",
    "TWO_OBSTACLE_PROTOCOL_CANDIDATE.md",
    "个人Agent_联络点协作候选.md",
    "潜入改线_关卡候选.md",
    "请本人到场_检查口关卡候选.md",
)
MOVED: dict[str, str] = {
    **{name: f"archive/concepts/{name}" for name in ROOT_CONCEPTS},
    "请本人到场_原文提取.md": "source_materials/story/请本人到场_原文提取.md",
    "output/protocol_room_level.png": "archive/concepts/protocol_room_level.png",
    "README_先读这里.md": "handoff/migration/README_迁移包.md",
    **{
        f"output/pdf/{name}": f"output/archive/submissions/{name}"
        for name in (
            *(
                f"AI_PLAY_72H_预赛方案_v0.{version}.{extension}"
                for version in range(1, 5)
                for extension in ("md", "pdf")
            ),
            *(
                f"AI_PLAY_72H_预赛方案_精炼特色版_v0.{version}.{extension}"
                for version in range(5, 8)
                for extension in ("md", "pdf")
            ),
        )
    },
    **{
        f"output/预赛玩法框架_v0.{version}.md": f"output/archive/briefs/预赛玩法框架_v0.{version}.md"
        for version in (2, 3)
    },
    "output/预赛材料修订记录_2026-11-14.md":
        "output/archive/reviews/预赛材料修订记录_2026-11-14.md",
}
OLD_FOR_NEW = {new: old for old, new in MOVED.items()}
LINK = re.compile(r"(\]\()([^()\n]+)(\))")


def relink(match: re.Match[str], old_source: str, new_source: str) -> str:
    """Return a link that points at the material's current location."""
    raw = match.group(2)
    if raw.startswith(("http:", "https:", "mailto:", "#", "data:", "//")):
        return match.group(0)
    target, separator, fragment = raw.partition("#")
    if not target or target.startswith("/"):
        return match.group(0)
    old_target = posixpath.normpath(posixpath.join(posixpath.dirname(old_source), target))
    used_root_fallback = False
    if old_target not in MOVED and not (ROOT / old_target).exists():
        # Several old Spec snapshots used root-relative paths while stored in output/archive.
        if target.startswith(("output/", "source_materials/", "tmp/")) or target in ROOT_CONCEPTS or (ROOT / target).exists():
            old_target = target
            used_root_fallback = True
    new_target = MOVED.get(old_target, old_target)
    if old_source == new_source and old_target == new_target and not used_root_fallback:
        return match.group(0)
    if not (ROOT / new_target).exists():
        return match.group(0)
    new_relative = posixpath.relpath(new_target, posixpath.dirname(new_source) or ".")
    return match.group(1) + new_relative + (separator + fragment if separator else "") + match.group(3)


def main() -> int:
    """Rebase links in Markdown files while leaving raw migration evidence intact."""
    modified = 0
    for path in ROOT.rglob("*.md"):
        relative = path.relative_to(ROOT).as_posix()
        if relative.startswith(("tools/", "tmp/", "handoff/migration/")):
            continue
        if relative in ("handoff/历次讨论记录.md",):
            continue
        old_source = OLD_FOR_NEW.get(relative, relative)
        before = path.read_text(encoding="utf-8")
        after = LINK.sub(lambda match: relink(match, old_source, relative), before)
        if after != before:
            path.write_text(after, encoding="utf-8", newline="")
            modified += 1
            print(relative)
    print(f"Modified {modified} Markdown files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
