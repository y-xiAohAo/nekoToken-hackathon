"""Assemble a self-contained, verified Windows migration of the hackathon workspace."""

from __future__ import annotations

import ast
import hashlib
import importlib.metadata as metadata
import json
import logging
import os
import re
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

from packaging.requirements import Requirement

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT.parent / "hackathon-migration-20261126"
STAGE = BUILD / "nekoToken-hackathon"
CODEX = Path("C:/Users/msn/.codex")
RUNTIME = Path("C:/Users/msn/.cache/codex-runtimes/codex-primary-runtime/dependencies")
TEMP = ROOT / "tmp/migration_20261126"
SOURCE_HISTORY = CODEX / "sessions/2026/11/09/rollout-2026-11-09T11-09-33-01a1be48-5338-7110-8b22-55454710a2a6.jsonl"
TEXT_SUFFIXES = {".md", ".txt", ".json", ".jsonl", ".toml", ".yaml", ".yml", ".html", ".py", ".js", ".ps1", ".sh", ".svg", ".csv", ".example"}
SKIP_PARTS = {"__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"}
SECRET_RE = re.compile(r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}\b|(?i:Bearer)\s+[A-Za-z0-9_.-]{32,}")


def safe_member(value: str) -> str:
    """Reject archive paths that could escape the extraction directory."""
    candidate = value.replace("\\", "/")
    parts = PurePosixPath(candidate).parts
    if not parts or candidate.startswith("/") or ":" in parts[0] or ".." in parts:
        raise ValueError(f"Unsafe archive member: {value}")
    return candidate


def redact_text(value: str) -> tuple[str, int]:
    """Remove token-shaped secrets without changing ordinary environment references."""
    return SECRET_RE.subn("[REDACTED_CREDENTIAL]", value)


def relocate_python(value: str) -> str:
    """Replace machine-specific authoring roots in the copied generator scripts."""
    discovery = "next(p for p in Path(__file__).resolve().parents if (p / 'PRELIMINARY_DESIGN_SPEC.md').is_file())"
    value = re.sub(r"Path\(['\"]D:/djh/search_agent/tms_optimizer/hackathon['\"]\)", discovery, value)
    value = value.replace('Path("D:/djh/简历/董骏豪的简历.pdf")', 'ROOT / "source_materials/resume/董骏豪的简历.pdf"')
    return value


def sha256(path: Path) -> str:
    """Hash a file with bounded memory usage."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def copy_tree(source: Path, target: Path) -> int:
    """Copy ordinary files, excluding reproducible Python bytecode caches."""
    count = 0
    for path in source.rglob("*"):
        if path.is_file() and not any(part in SKIP_PARTS for part in path.relative_to(source).parts):
            destination = target / path.relative_to(source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
            count += 1
    return count


def write_text(relative: str, value: str) -> None:
    """Write a UTF-8 file confined to the migration staging directory."""
    target = STAGE / safe_member(relative)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(value.rstrip() + "\n", encoding="utf-8")


def snapshot() -> list[dict[str, str | int | bool]]:
    """Copy all workspace materials and record integrity against the originals."""
    records: list[dict[str, str | int | bool]] = []
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT)
        if relative.parts[:2] in (("tmp", "migration_20261126"), ("output", "migration")):
            continue
        if path.name.startswith("wechat_") and relative.parts[0] == "tmp":
            continue
        destination = STAGE / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
        original_hash = sha256(path)
        if sha256(destination) != original_hash:
            raise ValueError(f"Snapshot mismatch: {relative}")
        records.append({"path": relative.as_posix(), "bytes": path.stat().st_size, "original_sha256": original_hash})
    logging.info("Workspace snapshot: %s files", len(records))
    return records


def collect_skills() -> list[dict[str, str | int]]:
    """Copy every available local skill, including its scripts and references."""
    sources = list((CODEX / "skills").glob("*/SKILL.md"))
    sources += list((CODEX / "skills/.system").glob("*/SKILL.md"))
    sources += list((CODEX / "plugins/cache/openai-primary-runtime").rglob("SKILL.md"))
    sources += list((CODEX / "plugins/cache/openai-bundled/visualize/1.0.49/skills").glob("*/SKILL.md"))
    local = STAGE / ".agents/skills"
    records: list[dict[str, str | int]] = []
    for existing in sorted(local.glob("*/SKILL.md")):
        records.append({"name": existing.parent.name, "origin": str(ROOT / existing.relative_to(STAGE)), "kind": "workspace"})
    for skill_file in sorted(sources):
        name = skill_file.parent.name
        if (local / name).exists():
            raise ValueError(f"Duplicate skill name: {name}")
        files = copy_tree(skill_file.parent, local / name)
        records.append({"name": name, "origin": str(skill_file.parent), "kind": "copied", "files": files})
    parent_skills = ROOT.parent / ".kimi/skills"
    for name in ("tms-optimizer-project", "tms-optimizer-codebase", "tms-optimizer-experiment", "tms-research-assistant", "tms-coding-discipline"):
        source = parent_skills / name
        if source.exists():
            copy_tree(source, STAGE / ".kimi/skills" / name)
    for name in ("sdd-riper-one", "vibe-coding-harness"):
        source = Path("C:/Users/msn/.kimi/skills") / name
        if source.exists():
            files = copy_tree(source, local / name)
            records.append({"name": name, "origin": str(source), "kind": "optional_protocol", "files": files})
    for name in ("vibe_coding_agent.md",):
        source = ROOT.parent / "agents" / name
        if source.exists():
            target = STAGE / "source_materials/engineering" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    hook = ROOT.parent / ".kimi/hooks/tms-coding-check.sh"
    if hook.exists():
        (STAGE / ".kimi/hooks").mkdir(parents=True, exist_ok=True)
        shutil.copy2(hook, STAGE / ".kimi/hooks" / hook.name)
    write_text("handoff/skills_inventory.json", json.dumps(records, ensure_ascii=False, indent=2))
    logging.info("Portable skill library: %s skills", len(records))
    return records


def collect_sources() -> list[dict[str, str]]:
    """Bring in the exact referenced originals and mark extra story drafts as supplementary."""
    wechat = Path("D:/djh/Wechat/Document/xwechat_files/wxid_i219l7ob5px722_9000/msg/file/2026-11")
    records: list[dict[str, str]] = []
    for name in ("背景故事素材.docx", "游戏背景v1(1).docx", "游戏背景v1.docx", "背景故事v2_2026至2042.md", "游戏背景——2026ai.docx", "游戏背景——2026.docx"):
        source = wechat / name
        if source.exists():
            dest = STAGE / "source_materials/story" / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)
            records.append({"path": dest.relative_to(STAGE).as_posix(), "original": str(source), "status": "previously_referenced" if name in ("背景故事素材.docx", "游戏背景v1(1).docx") else "supplementary_not_adopted"})
    for name in ("简历主文档.md", "董骏豪的简历.pdf"):
        source = Path("D:/djh/简历") / name
        destination = STAGE / "source_materials/resume" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        records.append({"path": destination.relative_to(STAGE).as_posix(), "original": str(source), "status": "source"})
    parent = STAGE / "source_materials/engineering/AGENTS.parent.original.md"
    parent.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT.parent / "AGENTS.md", parent)
    write_text("handoff/source_materials.json", json.dumps(records, ensure_ascii=False, indent=2))
    return records


def export_discussion() -> int:
    """Export human-visible user and assistant messages, excluding tools and hidden reasoning."""
    records: list[dict[str, str]] = []
    with SOURCE_HISTORY.open(encoding="utf-8") as handle:
        for line in handle:
            event = json.loads(line)
            payload = event.get("payload", {})
            if event.get("type") != "response_item" or payload.get("type") != "message":
                continue
            role = payload.get("role")
            if role not in ("user", "assistant"):
                continue
            if role == "assistant" and payload.get("channel") == "analysis":
                continue
            content = "\n".join(x.get("text", "") for x in payload.get("content", []) if x.get("type") in ("input_text", "output_text"))
            content = re.sub(r"<in-app-browser-context\b.*?</in-app-browser-context>", "", content, flags=re.S)
            if not content.strip() or content.lstrip().startswith(("<environment_context>", "# AGENTS.md instructions", "Another language model started")):
                continue
            content, _ = redact_text(content)
            records.append({"time": event.get("timestamp", ""), "role": role, "phase": payload.get("phase", ""), "text": content.strip()})
    write_text("handoff/conversation.jsonl", "\n".join(json.dumps(x, ensure_ascii=False) for x in records))
    sections = ["# 历次讨论记录\n\n只收录用户和助手可见文字，不包含工具返回、内部推理或登录信息。最新规则以接手说明和现行 Spec 为准。记录中的路径可能属于原电脑，请查 source_materials 与迁移清单。\n"]
    for index, message in enumerate(records, 1):
        title = "用户" if message["role"] == "user" else "助手"
        sections.append(f"## {index:03d} · {title} · {message['time']}\n\n{message['text']}\n")
    write_text("handoff/历次讨论记录.md", "\n".join(sections))
    logging.info("Exported visible discussion: %s messages", len(records))
    return len(records)


def copy_python_runtime() -> dict[str, str]:
    """Copy a relocatable Python 3.12 and only installed dependency closures used here."""
    source = RUNTIME / "python"
    target = STAGE / "tools/python"
    target.mkdir(parents=True, exist_ok=True)
    for path in source.iterdir():
        if path.is_file():
            shutil.copy2(path, target / path.name)
    for folder in ("DLLs", "Lib"):
        for path in (source / folder).rglob("*"):
            if not path.is_file():
                continue
            relative = path.relative_to(source)
            if "site-packages" in relative.parts or "__pycache__" in relative.parts:
                continue
            dest = target / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dest)
    roots = ["reportlab", "pillow", "pypdf", "python-docx", "pdfplumber", "pip", "packaging"]
    pending = list(roots)
    found: dict[str, str] = {}
    package_root = source / "Lib/site-packages"
    while pending:
        name = pending.pop()
        dist = metadata.distribution(name)
        canonical = dist.metadata["Name"].lower().replace("_", "-")
        if canonical in found:
            continue
        found[canonical] = dist.version
        for item in dist.files or []:
            path = Path(dist.locate_file(item)).resolve()
            if not path.is_file() or not path.is_relative_to(package_root) or "__pycache__" in path.parts:
                continue
            dest = target / "Lib/site-packages" / path.relative_to(package_root)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dest)
        for requirement_text in dist.requires or []:
            requirement = Requirement(requirement_text)
            if requirement.marker is None or requirement.marker.evaluate({"extra": ""}):
                pending.append(requirement.name)
    write_text("requirements.migration.lock.txt", "\n".join(f"{k}=={v}" for k, v in sorted(found.items())))
    # The image CLI SDK was installed into the workspace, outside source site-packages.
    image_packages = ROOT / "tmp/imagegen/cli-deps"
    for distribution in metadata.distributions(path=[str(image_packages)]):
        name = distribution.metadata["Name"].lower().replace("_", "-")
        if name in found:
            continue
        found[name] = distribution.version
        for item in distribution.files or []:
            path = Path(distribution.locate_file(item)).resolve()
            if path.is_file() and path.is_relative_to(image_packages) and "__pycache__" not in path.parts:
                dest = target / "Lib/site-packages" / path.relative_to(image_packages)
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, dest)
    write_text("requirements.migration.lock.txt", "\n".join(f"{k}=={v}" for k, v in sorted(found.items())))
    write_text("handoff/python_packages.json", json.dumps(found, indent=2))
    copy_tree(RUNTIME / "native/poppler/Library/bin", STAGE / "tools/poppler")
    (STAGE / "tools/node").mkdir(parents=True, exist_ok=True)
    shutil.copy2(RUNTIME / "node/bin/node.exe", STAGE / "tools/node/node.exe")
    logging.info("Copied portable Python and %s installed package distributions", len(found))
    return found


def patch_portable_copies() -> list[str]:
    """Relocate authoring scripts and scrub any detected credential literals in copies."""
    patched: list[str] = []
    for path in STAGE.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        if path.stat().st_size > 15 * 1024 * 1024 or path.is_relative_to(STAGE / "tools"):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        changed, count = redact_text(text)
        if path.suffix == ".py" and path.is_relative_to(STAGE / "tmp"):
            changed = relocate_python(changed)
        if changed != text:
            path.write_text(changed, encoding="utf-8")
            patched.append(path.relative_to(STAGE).as_posix())
        if count:
            logging.info("Removed credential-shaped text from %s", path.relative_to(STAGE))
    write_text("handoff/portable_changes.json", json.dumps(patched, ensure_ascii=False, indent=2))
    return patched


def create_manifest(snapshot_records: list[dict[str, str | int | bool]]) -> None:
    """Write exhaustive file hashes and original-workspace coverage."""
    for item in snapshot_records:
        path = STAGE / str(item["path"])
        item["portable_sha256"] = sha256(path)
        item["identical"] = item["original_sha256"] == item["portable_sha256"]
    write_text("handoff/workspace_coverage.json", json.dumps(snapshot_records, ensure_ascii=False, indent=2))
    entries = []
    for path in sorted(STAGE.rglob("*")):
        if path.is_file() and path.name != "MANIFEST.sha256.json" and path != STAGE / "handoff/target_check.json":
            entries.append({"path": path.relative_to(STAGE).as_posix(), "bytes": path.stat().st_size, "sha256": sha256(path)})
    write_text("MANIFEST.sha256.json", json.dumps({"created_utc": datetime.now(timezone.utc).isoformat(), "root": STAGE.name, "files": entries}, ensure_ascii=False, indent=2))


def build() -> None:
    """Assemble the staging directory without modifying any source material."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    if STAGE.exists():
        raise FileExistsError(f"Staging directory already exists: {STAGE}")
    STAGE.mkdir(parents=True)
    records = snapshot()
    skills = collect_skills()
    collect_sources()
    messages = export_discussion()
    packages = copy_python_runtime()
    documents = TEMP / "handoff_files"
    copy_tree(documents, STAGE)
    patches = patch_portable_copies()
    compile_count = 0
    for path in (STAGE / "tmp/pdfs").rglob("*.py"):
        ast.parse(path.read_text(encoding="utf-8-sig"))
        compile_count += 1
    write_text("handoff/package_summary.json", json.dumps({"workspace_file_count": len(records), "skill_count": len(skills), "discussion_messages": messages, "portable_python_packages": len(packages), "relocated_or_redacted_files": len(patches), "parsed_document_scripts": compile_count, "godot_project_exists": any(STAGE.rglob("project.godot")), "original_workspace": str(ROOT), "git_parent_not_included": str(ROOT.parent), "runtime_architecture": "Windows x86_64"}, ensure_ascii=False, indent=2))
    # Verification and final archive creation run after optional engine provisioning.
    create_manifest(records)
    logging.info("Staging ready: %s", STAGE)


if __name__ == "__main__":
    build()
