---
description: Generate a conventional commit message from staged changes
---
Analyze the git diff of staged changes and generate a conventional commit message.
Use the format: <type>(<scope>): <description>

Types: feat, fix, docs, style, refactor, test, chore

Git diff:
$(git diff --cached)

Additional context: {{args}}
