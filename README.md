# Desk Meter for Claude Code

A Claude Code plugin that shows your Claude usage limits on a small e-ink display on your desk. The display is an Elecrow CrowPanel ESP32 2.13" running the Claude Meter firmware.

You can see how much of your 5-hour session and weekly limit you've used without asking Claude or opening a browser. The meter also shows the current project, model, context window, cost and session time.

## How it works

Claude Code shares your usage limits only with its status line. So Desk Meter installs a small status line script that captures your latest usage each time the status line updates and forwards it to every meter you've added, over your local network. While you're idle it resends every few minutes so the meter can tell the data is still current.

Some sessions have no status line — most notably the **VS Code extension**. There Desk Meter runs the same script from `Stop` and `PostToolUse` hooks instead, so the meter still updates after each reply. Hooks aren't handed the full usage data the status line gets, so in that mode the script:

- reads the project, model and context use from the session transcript, and
- asks Anthropic for your session and weekly limits (at most once a minute), using your existing Claude Code login. It falls back to the last numbers the meter was sent if that call can't be made. Create `~/.config/desk-meter/no_usage_fetch` to turn the limit lookup off.

Sessions that *do* have a status line keep using its fuller data, and the hooks step aside for them, so you never get double updates.

- Sending happens in the background, so Claude Code never waits on the network.
- If you already had a status line, it keeps showing. Desk Meter runs alongside it.
- Nothing but the usage-limit lookup leaves your local network, and that goes only to Anthropic over your Claude Code login. There is no other cloud service or account.

## Install

You need a meter on the same Wi-Fi network as your computer, with `jq` and `curl` installed (see [Requirements](#requirements)).

In Claude Code:

```text
/plugin marketplace add DeskMeter/claude-plugin
/plugin install desk-meter@desk-meter
```

Then run:

```text
/desk-meter:setup
```

Setup checks for `jq` and `curl`, sets up the status line, finds meters on your network and asks for each meter's access token. The token is shown on the meter under **MENU > Info**. Setup then sends sample data. When the meter shows 42% session and 61% week, everything is working. Your real usage replaces the sample after Claude's next reply.

Usage limits are only available on Pro and Max plans. On other plans the meter still shows session details.

## Commands

| Command | What it does |
| --- | --- |
| `/desk-meter:setup` | Full setup: status line, find and add meters, test |
| `/desk-meter:add [host] [token]` | Add another meter |
| `/desk-meter:meters [remove HOST \| test]` | List, test or remove meters |
| `/desk-meter:uninstall` | Stop using the status line, restoring any previous one |

You can also run the helper script `plugin/scripts/desk-meter` directly from a terminal. Run it without arguments to see its commands.

## What gets sent

Desk Meter sends these to each meter you've added, over plain HTTP with the meter's access token:

- Session (5-hour) and weekly usage, and when each resets (Pro and Max plans only)
- Project name, model, effort level, context window usage, session cost, lines changed and session time

A status-line session sends all of these. A session with no status line (such as the VS Code extension) sends what it can read without one — project, model and context use, plus the session and weekly limits it looks up from Anthropic.

It sends after each of Claude's replies, at most once every 10 seconds (to protect the e-ink display). It also resends every 5 minutes so the meter can tell the data is still current. An update that arrives inside the 10-second window is held and sent once the window is up, so the last update of a burst isn't lost.

The connection to the meter is unencrypted, so use Desk Meter on a network you trust, such as your home Wi-Fi.

## Troubleshooting

**The meter shows as "not reachable".** Check that it's powered on and on the same Wi-Fi as your computer, then run `/desk-meter:meters` again.

**Add meters by name, not IP address.** Each meter has a name like `claude-meter-a1b2.local`, shown under MENU > Info. Your router can give the meter a new IP address every time it powers on, so an IP address that works today may stop working, or reach a different device, tomorrow. The name always finds the meter. If you added a meter by IP address, remove it and add it again by name:

```text
/desk-meter:meters remove 192.168.1.23
/desk-meter:add claude-meter-a1b2.local YOUR_TOKEN
```

**Setup finds no meters.** Some networks, such as office and guest Wi-Fi, block the discovery that setup uses. Add the meter by the name on its MENU > Info page instead.

## Files

Desk Meter keeps its settings in `~/.config/desk-meter/`:

- `devices`: one `host token` per line, readable only by you
- `fields`: your latest usage, sent to the meters
- `chain_command`: your previous status line command, which still shows
- `statusline.sh`: the script Claude Code runs (as a status line, and from hooks). It's refreshed from the plugin at the start of each session, so plugin updates take effect.
- `no_usage_fetch`: create this (empty) file to stop the usage-limit lookup used by hook mode

It also keeps small bookkeeping files here (`state`, `usage_next`, `sessions/`) for its send timing; you can ignore them.

The only setting it changes in `~/.claude/settings.json` is `statusLine`. It keeps a backup next to that file as `settings.json.desk-meter-backup`.

## Uninstall

Run `/desk-meter:uninstall` to restore your previous status line, then remove the plugin with `/plugin`. Your list of meters stays in `~/.config/desk-meter/` in case you set it up again. Delete that folder to remove it.

## Requirements

- macOS or Linux
- `jq` and `curl`. macOS 15 and later include both. On older macOS, run `brew install jq`. On Linux, install them with your package manager.
- Finding meters automatically uses `dns-sd` on macOS (built in) or `avahi-browse` on Linux. If you don't have either, add meters by name.

## License

[MIT](LICENSE)
