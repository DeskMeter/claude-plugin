# Desk Meter for Claude Code

A Claude Code plugin that shows your Claude usage limits on a small e-ink display on your desk. The display is an Elecrow CrowPanel ESP32 2.13" running the Claude Meter firmware.

You can see how much of your 5-hour session and weekly limit you've used without asking Claude or opening a browser. The meter also shows the current project, model, context window, cost and session time.

## How it works

Claude Code shares your usage limits only with its status line. So Desk Meter installs a small status line script. Each time the status line updates, the script sends your usage to every meter you've added, over your local network.

- Sending happens in the background, so your status line never waits on the network.
- If you already had a status line, it keeps showing. Desk Meter runs alongside it.
- Nothing leaves your local network. There is no cloud service or account.

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

It sends only when something has changed, at most once every 10 seconds. It also sends a heartbeat every 5 minutes so the meter can tell the data is still current.

The connection is unencrypted, so use Desk Meter on a network you trust, such as your home Wi-Fi.

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
- `chain_command`: your previous status line command, which still shows
- `statusline.sh`: the script Claude Code runs. It's refreshed from the plugin at the start of each session, so plugin updates take effect.

The only setting it changes in `~/.claude/settings.json` is `statusLine`. It keeps a backup next to that file as `settings.json.desk-meter-backup`.

## Uninstall

Run `/desk-meter:uninstall` to restore your previous status line, then remove the plugin with `/plugin`. Your list of meters stays in `~/.config/desk-meter/` in case you set it up again. Delete that folder to remove it.

## Requirements

- macOS or Linux
- `jq` and `curl`. macOS 15 and later include both. On older macOS, run `brew install jq`. On Linux, install them with your package manager.
- Finding meters automatically uses `dns-sd` on macOS (built in) or `avahi-browse` on Linux. If you don't have either, add meters by name.

## License

[MIT](LICENSE)
