#!/usr/bin/env bash
# Desk Meter status line.
#
# Claude Code runs this with session data as JSON on stdin. It:
#   1. forwards your usage to every e-ink meter you've added (in the background,
#      only when something changed, at most every 10 seconds), then
#   2. prints a status line: your previous status line command if you had one,
#      otherwise a short summary.
#
# Installed as a stable copy in ~/.config/desk-meter/ (refreshed every session),
# so it keeps working when the plugin updates.

CONF="${DESK_METER_HOME:-$HOME/.config/desk-meter}"
MIN_INTERVAL=10     # seconds between sends
HEARTBEAT=300       # resend unchanged data this often, so the meter knows we're alive

input=$(cat)

send_to_meters() {
  [ -s "$CONF/devices" ] || return 0
  command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 || return 0

  # One "key=value" line per field that is present.
  local fields
  fields=$(printf '%s' "$input" | jq -r '
    [ ["s",   .rate_limits.five_hour.used_percentage],
      ["sr",  .rate_limits.five_hour.resets_at],
      ["w",   .rate_limits.seven_day.used_percentage],
      ["wr",  .rate_limits.seven_day.resets_at],
      ["p",   (.workspace.repo.name
               // ((.workspace.project_dir // .workspace.current_dir // "") | split("/") | last))],
      ["m",   .model.display_name],
      ["e",   .effort.level],
      ["ctx", .context_window.used_percentage],
      ["cs",  .context_window.context_window_size],
      ["c",   .cost.total_cost_usd],
      ["la",  .cost.total_lines_added],
      ["lr",  .cost.total_lines_removed],
      ["d",   .cost.total_duration_ms] ]
    | .[] | select(.[1] != null and .[1] != "") | "\(.[0])=\(.[1])"' 2>/dev/null) || return 0
  [ -n "$fields" ] || return 0

  # Skip if nothing changed (ignoring the ever-ticking duration), except for a heartbeat.
  local now hash last_time last_hash
  now=$(date +%s)
  hash=$(printf '%s' "$fields" | grep -v '^d=' | cksum | cut -d' ' -f1)
  read -r last_time last_hash < "$CONF/state" 2>/dev/null
  last_time=${last_time:-0}
  [ $((now - last_time)) -lt "$MIN_INTERVAL" ] && return 0
  [ "$hash" = "$last_hash" ] && [ $((now - last_time)) -lt "$HEARTBEAT" ] && return 0
  printf '%s %s\n' "$now" "$hash" > "$CONF/state"

  local args=() ip=() kv host token
  while IFS= read -r kv; do args+=(--data-urlencode "$kv"); done <<< "$fields"

  while read -r host token _; do
    case "$host" in ''|'#'*) continue ;; esac
    # -4 for .local names: the meter doesn't answer IPv6 mDNS lookups, and
    # waiting for one costs ~3s of the 4s timeout.
    case "$host" in *.local|*.local:*) ip=(-4) ;; *) ip=() ;; esac
    curl "${ip[@]}" -s -m 4 -o /dev/null -G "http://$host/update" \
      --data-urlencode "token=$token" "${args[@]}" &
  done < "$CONF/devices"
  wait
}

# Send in the background so the status line never waits on the network.
( send_to_meters ) </dev/null >/dev/null 2>&1 &

# Status line output: the user's previous status line, if they had one.
if [ -s "$CONF/chain_command" ]; then
  printf '%s' "$input" | bash -c "$(cat "$CONF/chain_command")"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Desk Meter: install jq to see usage here"
  exit 0
fi

printf '%s' "$input" | jq -r '
  [ (.model.display_name // empty),
    (if .context_window.used_percentage != null
       then "context \(.context_window.used_percentage | floor)%" else empty end),
    (if .rate_limits.five_hour.used_percentage != null
       then "session \(.rate_limits.five_hour.used_percentage | floor)%" else empty end),
    (if .rate_limits.seven_day.used_percentage != null
       then "week \(.rate_limits.seven_day.used_percentage | floor)%" else empty end)
  ] | join(" · ")' 2>/dev/null
