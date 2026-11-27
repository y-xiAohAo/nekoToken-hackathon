"""Rebuild the checksum list for stable workspace materials."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_DIRECTORIES = {".git", ".godot", ".venv", "tools", "tmp", "build", "exports", "__pycache__"}
EXCLUDED_FILES = {"MANIFEST.sha256.json", "handoff/target_check.json"}


def included(path: Path) -> bool:
    """Return whether a file belongs to the stable project snapshot."""
    relative = path.relative_to(ROOT)
    return (
        path.is_file()
        and not any(part in EXCLUDED_DIRECTORIES for part in relative.parts)
        and relative.as_posix() not in EXCLUDED_FILES
        and not (path.name.startswith(".env") and path.name != ".env.example")
        and path.suffix != ".pyc"
    )


def main() -> int:
    """Write a deterministic path order with current sizes and SHA-256 digests."""
    entries = []
    for path in sorted(ROOT.rglob("*")):
        if not included(path):
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        entries.append({
            "path": path.relative_to(ROOT).as_posix(),
            "bytes": path.stat().st_size,
            "sha256": digest,
        })
    manifest = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "root": ROOT.name,
        "scope": "Stable project materials; excludes bundled runtime, temp files, caches and generated machine check",
        "files": entries,
    }
    target = ROOT / "MANIFEST.sha256.json"
    target.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(entries)} stable project files to {target.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
