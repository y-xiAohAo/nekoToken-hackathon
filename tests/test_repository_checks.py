"""Exercise portable repository checks without bundled tools or network access."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from check_project_links import check_links, collect_documents
from check_repository import tracked_paths, validate_paths


class RepositoryChecks(unittest.TestCase):
    """Use isolated files and Git indexes to test failure boundaries."""

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def write(self, name: str, content: str = "example\n") -> Path:
        """Create one UTF-8 fixture inside the temporary workspace."""
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def test_links_accept_existing_encoded_paths_and_external_urls(self) -> None:
        self.write("docs/中文 空格.md")
        page = self.write("README.md", "[doc](docs/中文%20空格.md#part)\n"
                          "[web](https://example.com/no-local-file) [part](#part)")
        self.assertEqual(check_links(self.root, [page]), [])

    def test_missing_link_and_missing_entry_fail(self) -> None:
        page = self.write("README.md", "[missing](docs/absent.md)")
        errors = check_links(self.root, [page, self.root / "missing.md"])
        self.assertEqual(len(errors), 2)

    def test_link_cannot_escape_repository(self) -> None:
        page = self.write("README.md", "[escape](../outside.md)")
        self.assertTrue(check_links(self.root, [page]))

    def test_markdown_examples_in_code_fences_are_not_links(self) -> None:
        page = self.write("README.md", "```markdown\n[example](not-a-file.md)\n```\n")
        self.assertEqual(check_links(self.root, [page]), [])

    def test_new_development_document_is_discovered(self) -> None:
        page = self.write("docs/decisions/0002-example.md")
        self.assertIn(page, collect_documents(self.root))

    def test_fresh_git_checkout_needs_no_bundled_runtime(self) -> None:
        self.write("README.md")
        self.write(".gitignore", "tmp/\ntools/\n")
        self.write("tmp/cache.txt")
        self.write("tools/runtime.txt")
        self.write("game/example.gd.uid")
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True,
                       capture_output=True)
        subprocess.run(["git", "-C", str(self.root), "add", "README.md"], check=True,
                       capture_output=True)
        paths = tracked_paths(self.root)
        self.assertIn(Path("README.md"), paths)
        self.assertIn(Path("game/example.gd.uid"), paths)
        self.assertNotIn(Path("tmp/cache.txt"), paths)
        self.assertEqual(validate_paths(self.root, paths), [])

    def test_tracked_cache_is_rejected_even_if_now_ignored(self) -> None:
        self.write("tmp/cache.txt")
        self.assertTrue(validate_paths(self.root, [Path("tmp/cache.txt")]))

    def test_source_assets_and_uid_metadata_are_allowed(self) -> None:
        names = ["game/example.gd.uid", "game/export_presets.cfg", ".env.example",
                 "archive/production/pdfs/report.json"]
        for name in names:
            self.write(name)
        self.assertEqual(validate_paths(self.root, [Path(x) for x in names]), [])

    def test_private_environment_and_key_files_are_rejected(self) -> None:
        for name in [".env.local", "game/release.pfx", "game/.godot/cache"]:
            self.write(name)
            with self.subTest(name=name):
                self.assertTrue(validate_paths(self.root, [Path(name)]))

    def test_missing_and_escaping_paths_are_rejected(self) -> None:
        self.assertTrue(validate_paths(self.root, [Path("missing.txt")]))
        self.assertTrue(validate_paths(self.root, [Path("../outside.txt")]))

    def test_large_file_requires_explicit_storage_decision(self) -> None:
        self.write("game/data.bin", "x" * 21)
        self.assertTrue(validate_paths(self.root, [Path("game/data.bin")], max_bytes=20))

    def test_token_detection_never_includes_token_in_diagnostic(self) -> None:
        token = "ghp_" + "A" * 36
        self.write("leak.txt", "token=" + token)
        errors = validate_paths(self.root, [Path("leak.txt")])
        self.assertTrue(errors)
        self.assertNotIn(token, "\n".join(errors))


if __name__ == "__main__":
    unittest.main()
