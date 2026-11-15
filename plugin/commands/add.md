---
description: Add an e-ink meter to Desk Meter
argument-hint: "[host] [token]"
---

Add an e-ink meter for Desk Meter. Arguments given: `$ARGUMENTS`

The helper script is `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter"`; run it with the Bash tool, quoted as written.

- If the arguments include both a host and a token, run `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter" add HOST TOKEN`.
- If the host is missing, run `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter" discover`, show what it finds, and ask which one to add.
- If the token is missing, ask for it. It's shown on the meter under MENU > Info.

After adding, run `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter" test` to confirm it works (it sends sample data to every meter), and tell the user the result in one line.
