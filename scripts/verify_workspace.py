"""Compatibility entry for the portable repository check; old migration checks are archived."""

from check_repository import main

if __name__ == "__main__":
    raise SystemExit(main())
