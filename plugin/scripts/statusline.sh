#!/usr/bin/env bash
# Desk Meter status line.
#
# Claude Code runs this with session data as JSON on stdin. It:
#   1. forwards your usage to every e-ink meter you've added (in the background,
#      only when something changed, at most every 10 seconds; an update that
#      arrives too soon is sent once the 10 seconds are up), then
#   2. prints a status line: your previous status line command if you had one
#      and it still works, otherwise a short summary.
#
# With --hook it is run from Claude Code hooks instead (Stop, PostToolUse). That
# covers sessions with no status line, such as the VS Code extension. It sends the
# project, model and context use (read from the transcript). Hooks don't get usage
# limits, so it asks Anthropic for them (at most once a minute) using your Claude
# Code login, and falls back to the last numbers the meter was sent. Create
# ~/.config/desk-meter/no_usage_fetch to turn that off.
#
# Installed as a stable copy in ~/.config/desk-meter/ (refreshed every session),
# so it keeps working when the plugin updates.

CONF="${DESK_METER_HOME:-$HOME/.config/desk-meter}"
FIELDS="$CONF/fields"      # latest data, one key=value per line
SESSIONS="$CONF/sessions"  # one marker file per session that has a status line
MIN_INTERVAL=10     # seconds between sends
HEARTBEAT=300       # resend unchanged data this often, so the meter knows we're alive

have_tools() {
  command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1
}

# Atomically replace the fields file with stdin.
write_fields() {
  local tmp
  tmp=$(mktemp "$CONF/fields.XXXXXX") || return 1
  cat > "$tmp" && mv "$tmp" "$FIELDS"
}

send_now() {
  local args=() ip=() kv host token
  while IFS= read -r kv; do
    [ -n "$kv" ] && args+=(--data-urlencode "$kv")
  done < "$FIELDS"
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

# Send the latest fields if they changed (ignoring the ever-ticking duration) or
# the heartbeat is due. Too soon after the last send, wait out the interval and
# then send whatever is newest, so the final update of a burst isn't lost.
flush() {
  [ -s "$FIELDS" ] && [ -s "$CONF/devices" ] || return 0
  local now hash last_time last_hash wait
  now=$(date +%s)
  hash=$(grep -v '^d=' "$FIELDS" | cksum | cut -d' ' -f1)
  read -r last_time last_hash < "$CONF/state" 2>/dev/null
  last_time=${last_time:-0}
  [ "$hash" = "$last_hash" ] && [ $((now - last_time)) -lt "$HEARTBEAT" ] && return 0

  wait=$((last_time + MIN_INTERVAL - now))
  if [ "$wait" -gt 0 ]; then
    # Only one waiter at a time; clear a lock left behind by a killed one.
    find "$CONF/waiting" -maxdepth 0 -mmin +1 -exec rmdir {} \; 2>/dev/null
    if mkdir "$CONF/waiting" 2>/dev/null; then
      sleep "$wait"
      rmdir "$CONF/waiting" 2>/dev/null
      flush
    fi
    return 0
  fi

  printf '%s %s\n' "$now" "$hash" > "$CONF/state"
  send_now
}

# ---------------------------------------------------------------- hook mode

USAGE_URL="https://api.anthropic.com/api/oauth/usage"
USAGE_EVERY=60      # seconds between usage fetches
USAGE_BACKOFF=600   # after a failed fetch, wait this long before trying again

# Print Claude Code's OAuth access token, if it's stored and not expired.
oauth_token() {
  local creds
  if command -v security >/dev/null 2>&1; then   # macOS Keychain
    creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  fi
  if [ -z "$creds" ]; then
    local file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
    [ -r "$file" ] && creds=$(cat "$file")
  fi
  [ -n "$creds" ] || return 1
  printf '%s' "$creds" | jq -r --argjson now "$(date +%s)" '
    .claudeAiOauth | select(.accessToken != null)
    | select((.expiresAt // 0) == 0 or .expiresAt / 1000 > $now + 30)
    | .accessToken' 2>/dev/null | grep .
}

# Print fresh "s= sr= w= wr=" lines from Anthropic, rate limited. The token is
# passed to curl on stdin so it never appears in the process list.
fetch_usage() {
  [ -e "$CONF/no_usage_fetch" ] && return 1
  local now next token body code
  now=$(date +%s)
  read -r next < "$CONF/usage_next" 2>/dev/null
  [ "$now" -lt "${next:-0}" ] 2>/dev/null && return 1
  echo $((now + USAGE_BACKOFF)) > "$CONF/usage_next"   # assume failure until it works

  token=$(oauth_token) || return 1
  body=$(printf 'header = "Authorization: Bearer %s"\n' "$token" \
    | curl -s -m 8 -w '\n%{http_code}' -K - \
        -H "anthropic-beta: oauth-2025-04-20" "$USAGE_URL" 2>/dev/null)
  code=${body##*$'\n'}
  body=${body%$'\n'*}
  [ "$code" = 200 ] || return 1

  local fields
  fields=$(printf '%s' "$body" | jq -r '
    def epoch: if type == "number" then . else try (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) catch null end;
    [ ["s",  .five_hour.utilization],
      ["sr", (.five_hour.resets_at // null | if . then epoch else null end)],
      ["w",  .seven_day.utilization],
      ["wr", (.seven_day.resets_at // null | if . then epoch else null end)] ]
    | .[] | select(.[1] != null) | "\(.[0])=\(.[1])"' 2>/dev/null)
  printf '%s\n' "$fields" | grep -q '^s=' || return 1

  echo $((now + USAGE_EVERY)) > "$CONF/usage_next"
  printf '%s\n' "$fields"
}

hook_update() {
  local hook sid transcript cwd project latest cs
  hook=$1
  sid=$(printf '%s' "$hook" | jq -r '.session_id // empty')
  # Sessions with a status line already send fuller data from there.
  [ -n "$sid" ] && [ -e "$SESSIONS/$sid" ] && return 0
  transcript=$(printf '%s' "$hook" | jq -r '.transcript_path // empty')
  cwd=$(printf '%s' "$hook" | jq -r '.cwd // empty')

  if [ -n "$cwd" ]; then
    project=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
    project=$(basename "${project:-$cwd}")
  fi

  # Model and context use from the last main-thread reply in the transcript.
  if [ -f "$transcript" ]; then
    latest=$(tail -n 300 "$transcript" | jq -R -n -r '
      [ inputs | fromjson? | select(.type == "assistant" and (.isSidechain | not)
          and .message.usage != null and .message.model != "<synthetic>") ]
      | last // empty
      | "\(.message.model) \(.message.usage
          | (.input_tokens // 0) + (.cache_creation_input_tokens // 0)
            + (.cache_read_input_tokens // 0))"' 2>/dev/null)
  fi

  local model="" used="" fields=""
  read -r model used <<< "$latest"
  [ -n "$project" ] && fields="p=$project"
  if [ -n "$model" ]; then
    # claude-opus-5-5 -> Opus 5.5
    model=$(printf '%s' "$model" | jq -R -r '
      sub("\\[.*\\]$"; "") | sub("^claude-"; "") | sub("-[0-9]{8}$"; "")
      | split("-") | (.[0][0:1] | ascii_upcase) + .[0][1:]
        + (if length > 1 then " " + (.[1:] | join(".")) else "" end)')
    fields="$fields"$'\n'"m=$model"
  fi
  if [ -n "$used" ] && [ "$used" -gt 0 ] 2>/dev/null; then
    cs=$(sed -n 's/^cs=//p' "$FIELDS" 2>/dev/null)
    case "$cs" in ''|*[!0-9]*) cs=200000 ;; esac
    [ "$used" -gt "$cs" ] && cs=1000000
    fields="$fields"$'\n'"ctx=$((used * 100 / cs))"$'\n'"cs=$cs"
  fi
  local usage
  usage=$(fetch_usage) && fields="$fields"$'\n'"$usage"
  [ -n "$fields" ] || return 0

  # Keep everything else (usage limits, cost...) from the last full update.
  touch "$FIELDS"
  awk -F= 'NR == FNR { if ($0 != "") { seen[$1] = 1; print } next } !($1 in seen)' \
    <(printf '%s\n' "$fields") "$FIELDS" | write_fields
  flush
}

if [ "${1:-}" = "--hook" ]; then
  hook=$(cat)
  have_tools && [ -s "$CONF/devices" ] || exit 0
  ( hook_update "$hook" ) </dev/null >/dev/null 2>&1 &
  exit 0
fi

# ----------------------------------------------------------- status line mode

input=$(cat)

statusline_update() {
  [ -s "$CONF/devices" ] && have_tools || return 0

  local sid
  sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
  if [ -n "$sid" ]; then
    mkdir -p "$SESSIONS" && touch "$SESSIONS/$sid"
    find "$SESSIONS" -type f -mtime +2 -delete 2>/dev/null
  fi

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

  printf '%s\n' "$fields" | write_fields && flush
}

# Send in the background so the status line never waits on the network.
( statusline_update ) </dev/null >/dev/null 2>&1 &

# Status line output: the user's previous status line, if it still works.
if [ -s "$CONF/chain_command" ]; then
  out=$(printf '%s' "$input" | bash -c "$(cat "$CONF/chain_command")" 2>/dev/null)
  if [ $? -eq 0 ] && [ -n "$out" ]; then
    printf '%s\n' "$out"
    exit 0
  fi
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
