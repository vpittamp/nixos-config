# Feature 096 Project CRUD Tests

This directory keeps the non-UI project CRUD tests that still exercise the
legacy `ProjectEditor` compatibility surface.

The old Eww monitoring-panel UI tests and debugging helpers are retired. Runtime
desktop validation now goes through QuickShell, `i3pm health`, and focused
daemon/CLI tests.

Run the retained tests with:

```bash
python -m pytest tests/096-bolster-project-and/unit tests/096-bolster-project-and/integration -q
```
