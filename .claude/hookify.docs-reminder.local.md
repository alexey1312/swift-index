---
name: docs-reminder-after-code-changes
enabled: true
event: stop
action: warn
pattern: .*
---

## Documentation Check

Before finishing, consider if documentation needs updating.

**Update documentation if you:**
- Added new public APIs, commands, or features
- Changed existing behavior or signatures
- Modified configuration options or environment variables
- Fixed bugs that affect documented behavior
- Changed architecture or module structure

**Skip documentation update if you:**
- Only did research or exploration
- Only created plans or proposals
- Made internal refactoring with no API changes
- Fixed bugs with no user-visible behavior change
- Updated tests only

**Files to check:**
- `CLAUDE.md` — Project guide, commands, architecture
- `README.md` — User-facing documentation
- Code comments/docstrings for public APIs
- OpenSpec proposals in `/openspec/` (if architectural changes)

If code changes warrant documentation updates, do them now before completing the task.
