---
description: Set up Desk Meter - status line plus your e-ink meters
---

Set up Desk Meter so Claude Code sends the user's usage to their e-ink meter(s).

The helper script is `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter"`. Run it with the Bash tool exactly as written, quoted. Keep your messages to the user short.

1. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter" doctor`. If `jq` or `curl` is missing, tell the user how to install it (macOS: `brew install jq`) and stop until they have.

2. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter" install-statusline`. Tell the user in one line what it changed. If it kept their previous status line, say that it still shows. If it refuses because their settings file has comments, show them the line to add themselves.

3. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter" discover` and show the meters it found.
   - If it found none, ask the user for the meter's address, which is on the meter under MENU > Info (for example `claude-meter-a1b2.local`).

4. Ask the user for each meter's access token, also shown under MENU > Info. Ask for all of them in one message if there are several. Then for each meter run `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter" add HOST TOKEN`. If a token is rejected, ask them to re-check it.

5. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/desk-meter" test` and ask the user to confirm each meter now shows 42% session and 61% week.

6. Finish with one or two lines: real usage replaces the sample after Claude's next reply, and usage limits only appear for Pro and Max plans. Mention `/desk-meter:meters` for managing meters later.
