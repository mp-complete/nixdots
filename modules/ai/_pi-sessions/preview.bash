# pi-sessions-preview <session file> <tmux pane>
#
# Preview command for the `pi-sessions` tv channel. A running session that
# lives in a tmux pane previews as that pane's live contents -- what the agent
# is doing *right now*, tool output and all. Everything else (no tmux, a
# session that outlived its pane, a plain on-disk transcript) falls back to a
# rendered tail of the session JSONL.

file=${1:--}
pane=${2:--}

c_hdr=$'\033[1;35m'
c_user=$'\033[1;36m'
c_asst=$'\033[1;32m'
c_tool=$'\033[2;37m'
c_off=$'\033[0m'

# --- live pane ------------------------------------------------------------
# `-t %12` is a pane id, unique across the whole server, so no session/window
# name disambiguation is needed. It fails harmlessly once the pane is gone.
if [ "$pane" != - ] && [ -n "${pane}" ]; then
    if out=$(tmux capture-pane -p -t "$pane" 2>/dev/null); then
        printf '%s%s%s\n\n' "$c_hdr" "── live: pane $pane ──" "$c_off"
        # Strip the trailing blank block tmux pads the pane out with.
        printf '%s\n' "$out" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
        exit 0
    fi
fi

# --- transcript -----------------------------------------------------------
if [ "$file" = - ] || [ ! -f "$file" ]; then
    printf '%sno transcript%s\n\n(ephemeral session, or the file was deleted)\n' "$c_hdr" "$c_off"
    exit 0
fi

head -n 1 -- "$file" | jq -r --arg h "$c_hdr" --arg o "$c_off" '
    "\($h)── \(.cwd // "?") ──\($o)\nsession \(.id // "?")   started \(.timestamp // "?")"' 2>/dev/null

printf '\n'

# The tail bound is what keeps this instant on a multi-megabyte transcript;
# tools and thinking blocks collapse to one line each so the actual
# conversation stays legible.
tail -n 400 -- "$file" | jq -r \
    --arg u "$c_user" --arg a "$c_asst" --arg t "$c_tool" --arg o "$c_off" '
    select(.type == "message") | .message as $m
    | ($m.timestamp // 0 | if . > 0 then (. / 1000 | strflocaltime("%H:%M")) else "" end) as $ts
    | if ($m.content | type) == "string" then [$m.content]
      else [ $m.content[]?
             | if .type == "text" then .text
               elif .type == "toolCall" then "\($t)→ \(.name) \((.arguments | tostring)[0:120])\($o)"
               elif .type == "thinking" then "\($t)· thinking\($o)"
               else empty end ]
      end as $parts
    | ($parts | join("\n")) as $raw
    | (if $m.role == "user" or $m.role == "assistant" then $raw[0:1500]
       else ($raw | split("\n")[0:4] | join("\n"))[0:400] end) as $body
    | select($body | length > 0)
    | if $m.role == "user" then "\($u)▌user \($ts)\($o)"
      elif $m.role == "assistant" then "\($a)▌assistant \($ts)\($o)"
      else "\($t)▌\($m.role) \($ts)\($o)" end
    | . + "\n" + $body + "\n"' 2>/dev/null
