"""Verify all migration payload hashes and report target-machine prerequisites."""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import logging
import os
import shutil
import subprocess
import sys
from pathlib import Path, PurePosixPath

from rebuild_manifest import included


def main() -> int:
    """Validate content and return nonzero only for missing or corrupt package files."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--quick", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads((root / "MANIFEST.sha256.json").read_text(encoding="utf-8"))
    failures: list[str] = []
    listed: set[str] = set()
    for item in manifest["files"]:
        relative = PurePosixPath(item["path"])
        if relative.is_absolute() or ".." in relative.parts or ":" in relative.parts[0]:
            failures.append(f"Unsafe path: {relative}")
            continue
        listed.add(relative.as_posix())
        path = root / str(relative)
        if not path.is_file():
            failures.append(f"Missing: {relative}")
            continue
        if path.stat().st_size != item["bytes"]:
            failures.append(f"Size mismatch: {relative}")
            continue
        if not args.quick:
            digest = hashlib.file_digest(path.open("rb"), "sha256").hexdigest()
            if digest != item["sha256"]:
                failures.append(f"Hash mismatch: {relative}")
    for path in root.rglob("*"):
        if included(path):
            relative = path.relative_to(root).as_posix()
            if relative not in listed:
                failures.append(f"Unlisted project file: {relative}")
    skills = sorted((root / ".agents/skills").glob("*/SKILL.md"))
    packages: dict[str, bool] = {}
    for name in ("PIL", "reportlab", "pypdf", "docx", "openai", "httpx2", "pdfplumber"):
        try:
            importlib.import_module(name)
            packages[name] = True
        except ImportError:
            packages[name] = False
            failures.append(f"Bundled Python import failed: {name}")
    tool_checks: dict[str, bool] = {}
    for name, command in {"node": [str(root / "tools/node/node.exe"), "--version"],
                          "pdfinfo": [str(root / "tools/poppler/pdfinfo.exe"), "-v"]}.items():
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=15, encoding="utf-8", errors="replace")
            tool_checks[name] = result.returncode == 0
            if result.returncode:
                failures.append(f"Bundled tool failed: {name}")
        except (OSError, subprocess.TimeoutExpired) as error:
            failures.append(f"Bundled tool unavailable: {name}: {error}")
            tool_checks[name] = False
    report = {"root": str(root), "files_checked": len(manifest["files"]), "manifest_scope": manifest.get("scope"), "full_hashes": not args.quick,
              "skill_count": len(skills), "python": sys.version, "packages": packages, "bundled_tools": tool_checks,
              "git": shutil.which("git"), "godot": shutil.which("godot") or shutil.which("godot4"),
              "godot_project_exists": any(root.rglob("project.godot")),
              "chinese_font_exists": Path("C:/Windows/Fonts/msyh.ttc").exists(),
              "api_key_in_environment": bool(os.environ.get("OPENAI_API_KEY")), "failures": failures}
    (root / "handoff/target_check.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    logging.info("Project files: %s; skills: %s; integrity issues: %s", len(manifest["files"]), len(skills), len(failures))
    logging.info("Bundled imports and tools: %s / %s", packages, tool_checks)
    logging.info("Git: %s; Godot: %s; project.godot: %s", report["git"] or "install required", report["godot"] or "install required", report["godot_project_exists"])
    logging.info("Agent client, plugin services and real model access require checks on the destination machine.")
    for failure in failures:
        logging.error(failure)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
