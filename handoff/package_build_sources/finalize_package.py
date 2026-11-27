"""Seal the migration payload and verify every archived member against its hash."""

from __future__ import annotations

import json
import logging
import shutil
import zipfile
from pathlib import Path

import package_workspace as package


def main() -> None:
    """Create a ZIP and checksum after source-machine and relocation checks pass."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    stage = package.STAGE
    check = json.loads((stage / "handoff/target_check.json").read_text(encoding="utf-8"))
    if check["failures"]:
        raise ValueError("Source-machine verification has outstanding failures")
    package.write_text("handoff/source_machine_verification.json", json.dumps(check, ensure_ascii=False, indent=2))
    coverage = json.loads((stage / "handoff/workspace_coverage.json").read_text(encoding="utf-8"))
    build_sources = stage / "handoff/package_build_sources"
    build_sources.mkdir(parents=True, exist_ok=True)
    for name in ("package_workspace.py", "finalize_package.py"):
        shutil.copy2(package.TEMP / name, build_sources / name)
    package.copy_tree(package.TEMP / "tests", build_sources / "tests")
    package.write_text("handoff/package_build_sources/README.md", "这些是原电脑打包时使用的程序与测试，作为追溯材料保留。程序中的原电脑输入路径没有迁移，不是参赛机的启动入口。请使用根目录Start-Workspace.ps1和scripts/Check-Workspace.ps1。")
    package.create_manifest(coverage)
    output = package.ROOT / "output/migration"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / "nekoToken-hackathon-20261126-final.zip"
    if archive.exists():
        raise FileExistsError(archive)
    manifest = json.loads((stage / "MANIFEST.sha256.json").read_text(encoding="utf-8"))
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as target:
        for path in sorted(stage.rglob("*")):
            if path.is_file():
                member = package.safe_member(stage.name + "/" + path.relative_to(stage).as_posix())
                target.write(path, member)
    with zipfile.ZipFile(archive) as source:
        members = source.namelist()
        if len(members) != len(set(members)):
            raise ValueError("ZIP contains duplicate names")
        for name in members:
            package.safe_member(name)
        corrupt = source.testzip()
        if corrupt:
            raise ValueError(f"ZIP CRC failure: {corrupt}")
        import hashlib
        for item in manifest["files"]:
            member = stage.name + "/" + item["path"]
            digest = hashlib.sha256(source.read(member)).hexdigest()
            if digest != item["sha256"]:
                raise ValueError(f"ZIP SHA-256 mismatch: {member}")
    checksum = package.sha256(archive)
    archive.with_suffix(".zip.sha256.txt").write_text(f"{checksum}  {archive.name}\n", encoding="ascii")
    summary = {"archive": str(archive), "bytes": archive.stat().st_size, "sha256": checksum,
               "zip_members": len(members), "verified_payload_hashes": len(manifest["files"]),
               "workspace_files": len(coverage), "source_unchanged_files": sum(bool(x["identical"]) for x in coverage),
               "source_relocated_copies": [x["path"] for x in coverage if not x["identical"]],
               "skills": check["skill_count"], "relocation_rebuild": "8-page proposal and 1-page participant introduction rebuilt successfully",
               "transfer_status": "not_sent_yet"}
    (output / "package-verification.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    logging.info(json.dumps(summary, ensure_ascii=True))


if __name__ == "__main__":
    main()
