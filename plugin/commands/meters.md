---
description: List, test or remove your Desk Meter e-ink meters
argument-hint: "[remove HOST | test]"
---

Manage the user's Desk Meter meters. Arguments given: `$ARGUMENTS`

The helper script is `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter"`; run it with the Bash tool, quoted as written.

- No arguments: run `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter" list` and show the result. If any meter isn't reachable, suggest checking it's powered and on the same Wi-Fi.
- `remove HOST`: run `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter" remove HOST`.
- `test`: run `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter" test` and ask the user to check each meter shows 42% session and 61% week.

To add a meter, the user can run `/desk-meter:add`.
