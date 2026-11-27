"""Validate migration paths, secret filtering, and document relocation rules."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from package_workspace import redact_text, relocate_python, safe_member


class MigrationSafetyTests(unittest.TestCase):
    """Check archive boundaries and preservation of useful source text."""

    def test_archive_member_rejects_parent_and_absolute_paths(self) -> None:
        for value in ("../outside.txt", "/absolute.txt", "C:/private.txt", "x/../../bad"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                safe_member(value)

    def test_archive_member_keeps_unicode_names(self) -> None:
        self.assertEqual(safe_member("output/请本人到场.pdf"), "output/请本人到场.pdf")

    def test_redaction_removes_real_looking_bearer_and_key(self) -> None:
        fake = "sk-" + "A1b2" * 12
        result, count = redact_text(f"key={fake}\nAuthorization: Bearer {fake}")
        self.assertNotIn(fake, result)
        self.assertGreaterEqual(count, 1)

    def test_redaction_preserves_env_references_and_placeholders(self) -> None:
        original = "os.environ['OPENAI_API_KEY']\nOPENAI_API_KEY=\napi_key=YOUR_API_KEY"
        result, count = redact_text(original)
        self.assertEqual(result, original)
        self.assertEqual(count, 0)

    def test_relocation_finds_root_and_moves_resume_reference(self) -> None:
        original = (
            "from pathlib import Path\n"
            "ROOT = Path('D:/djh/search_agent/tms_optimizer/hackathon')\n"
            'SOURCE_PDF = Path("D:/djh/简历/董骏豪的简历.pdf")\n'
        )
        relocated = relocate_python(original)
        compile(relocated, "portable.py", "exec")
        self.assertNotIn("D:/djh/", relocated)
        self.assertIn("__file__", relocated)
        self.assertIn("source_materials", relocated)


if __name__ == "__main__":
    unittest.main()
