"""Read the supplied story document and compare local story sources."""

from __future__ import annotations

import sys
from pathlib import Path

from docx import Document


def dump(path: Path) -> None:
    doc = Document(path)
    print(f"### {path.name} | paragraphs={len(doc.paragraphs)} tables={len(doc.tables)}")
    for index, paragraph in enumerate(doc.paragraphs, start=1):
        text = paragraph.text.strip()
        if text:
            print(f"P{index:03d} [{paragraph.style.name}] {text}")
    for table_index, table in enumerate(doc.tables, start=1):
        print(f"TABLE {table_index} rows={len(table.rows)}")
        for row_index, row in enumerate(table.rows, start=1):
            print(f"T{table_index}.{row_index} " + " | ".join(cell.text.replace("\n", "; ") for cell in row.cells))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    for name in sys.argv[1:]:
        dump(Path(name))
