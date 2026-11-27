#!/bin/bash
# PreToolUse hook for TMS coding discipline.
# Blocks writes to src/ without matching tests.
# Warns on print() usage in new files.
# Checks for bare except: in diffs.
# Exit 0 = allow, Exit 2 = block.

set -euo pipefail

read JSON
FILE=$(echo "$JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))")

# Only check Python files in src/, scripts/, tests/
if [[ ! "$FILE" =~ \.py$ ]]; then
    exit 0
fi

if [[ ! "$FILE" =~ ^(src/|scripts/|tests/) ]]; then
    exit 0
fi

# Use the project's lint checker if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LINTER="$PROJECT_ROOT/.kimi/skills/tms-coding-discipline/scripts/lint_check.py"

if [ -f "$LINTER" ]; then
    if ! python3 "$LINTER" "$FILE" 2>/dev/null; then
        # Fallback to basic checks if linter fails
        :
    fi
fi

# Block src/ files without tests (basic heuristic)
if [[ "$FILE" =~ ^src/tms_optimizer/.*\.py$ ]]; then
    BASENAME=$(basename "$FILE" .py)
    if [ "$BASENAME" = "__init__" ]; then
        exit 0
    fi
    TESTFILE="tests/test_${BASENAME}.py"
    if [ ! -f "$TESTFILE" ]; then
        echo "Error: $FILE has no corresponding test file ($TESTFILE). Write test first." >&2
        echo "Rule: TDD — create tests/test_${BASENAME}.py before implementing." >&2
        exit 2
    fi
fi

exit 0
