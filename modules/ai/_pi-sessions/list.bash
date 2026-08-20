# pi-sessions-list <active|project|recent>
#
# Emits one TAB-separated row per session, for the `pi-sessions` tv channel
# (modules/ai/pi-sessions.nix):
#
#   <display>\t<session id>\t<session file>\t<tmux pane>
#
# Columns 1..3 feed the channel's `output` template and its preview command;
# only column 0 is ever shown. Missing values are "-" rather than empty so the
# tab layout never collapses.
#
# "Active" comes from pi-presence's state files
# (`<agentDir>/live/<session id>.json`), not from process inspection: pi keeps
# no handle on its session JSONL and exports PI_SESSION_FILE only into bash
# tool children, so a pid cannot otherwise be mapped back to a session.
#
# Everything here is fork-averse -- this runs on every channel switch over a
# few hundred session files, and a `$(…)` per row is what makes a picker feel
# slow. Helpers return through $REPLY, timestamps come from `find -printf`
# rather than `stat`, and all the JSONL parsing is one `jq` for the whole list.

mode=${1:-active}
now=$(date +%s)

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# Every pi config dir on this host: the default one plus the `configDir`
# variants the wrapper builds (`pi-msft` -> ~/.config/pi-msft), whose sessions
# and live files are separate trees.
agent_dirs() {
    local d
    for d in "$HOME/.pi/agent" "$HOME"/.config/pi-*/agent; do
        [ -d "$d" ] && printf '%s\n' "$d"
    done
}

fmt_age() {
    local s=$1
    [ "$s" -lt 0 ] && s=0
    if [ "$s" -lt 60 ]; then
        REPLY="${s}s"
    elif [ "$s" -lt 3600 ]; then
        REPLY="$((s / 60))m"
    elif [ "$s" -lt 86400 ]; then
        REPLY="$((s / 3600))h"
    else
        REPLY="$((s / 86400))d"
    fi
}

# All four icons are double-width emoji so the columns after them stay
# aligned. The set is empirical, not aesthetic: tv 0.15.9 draws several
# otherwise obvious candidates (⛔ ✅ ⚠ ❗ 🟢 ✔) as ␀ placeholders, so check any
# replacement with
#   tv --source-command 'printf "<candidate> x\n"'
# before swapping one in.
icon_for() {
    case $1 in
        blocked) REPLY='🙋' ;;
        working) REPLY='⚡' ;;
        idle) REPLY='🔵' ;;
        *) REPLY='💤' ;;
    esac
}

# ---------------------------------------------------------------------------
# live state (pi-presence)
# ---------------------------------------------------------------------------

# id \t state \t cwd \t model \t branch \t updatedAt(s) \t pid \t pane \t name \t file
live_rows() {
    local d f
    while read -r d; do
        for f in "$d"/live/*.json; do
            [ -e "$f" ] || continue
            jq -r '
                select((.schema // 1) <= 1)
                | [ .sessionId,
                    (.state // "idle"),
                    (.cwd // "-"),
                    (.model // "-"),
                    (.branch // "-"),
                    (((.updatedAt // 0) / 1000) | floor),
                    (.pid // 0),
                    (.terminal.tmuxPane // "-"),
                    (.sessionName // "-"),
                    (.sessionFile // "-") ]
                | @tsv' "$f" 2>/dev/null
        done
    done < <(agent_dirs)
}

# pi-presence unlinks its state file on every teardown, so a surviving file
# whose pid is gone means the session died hard (crash, SIGKILL, closed
# terminal). Those stay listed as dormant -- the transcript is still resumable.
alive() { [ "$1" -gt 0 ] && kill -0 "$1" 2>/dev/null; }

# ---------------------------------------------------------------------------
# on-disk sessions
# ---------------------------------------------------------------------------

# Session dir for a cwd: pi encodes it by replacing every "/" with "-" and
# wrapping the result in "--" … "--".
session_dir_for() {
    local d enc="--${1#/}--"
    enc=${enc//\//-}
    while read -r d; do
        [ -d "$d/sessions/$enc" ] && printf '%s\n' "$d/sessions/$enc"
    done < <(agent_dirs)
}

# Newest-first session files across the given roots, as "<mtime>\t<path>".
# -maxdepth 2 keeps subagent transcripts (`<session>/<hash>/run-N/session.jsonl`)
# out of the list.
session_files() {
    local limit=$1
    shift
    [ $# -gt 0 ] || return 0
    find "$@" -mindepth 1 -maxdepth 2 -name '*.jsonl' -printf '%T@\t%p\n' 2>/dev/null |
        sort -rn | head -n "$limit" | sed 's/\.[0-9]*\t/\t/'
}

# stdin: session file paths, one per line (any order).
# stdout: <path>\t<cwd>\t<name>\t<first user prompt>, input order preserved.
#
# Only the head of each file is read: a live transcript runs to megabytes, but
# the session header is line 1 and the opening prompt is right behind it. A
# `/name` set later in the conversation is missed by design -- that is the
# price of not reading 274 MB to draw a list.
summarize() {
    local f
    while read -r f; do
        printf '\036%s\n' "$f"
        head -n 25 -- "$f" 2>/dev/null
    done | jq -Rrn '
        def txt($c): if ($c | type) == "string" then $c
                     else ([$c[]? | select(.type == "text") | .text] | first) end;
        reduce inputs as $l ({cur: null, out: []};
          if ($l | startswith("\u001e")) then
            (if .cur then .out += [.cur] else . end)
            | .cur = {f: $l[1:], cwd: "-", name: "-", p: "-"}
          elif .cur == null then .
          else ($l | fromjson? // null) as $j
            | if $j == null then .
              elif $j.type == "session" then .cur.cwd = ($j.cwd // "-")
              elif $j.type == "session_info" then .cur.name = ($j.name // .cur.name)
              elif ($j.type == "message" and $j.message.role == "user" and .cur.p == "-")
                then .cur.p = (txt($j.message.content) // "-")
              else . end
          end)
        | (if .cur then .out + [.cur] else .out end)[]
        | [.f, .cwd, .name, ((.p | gsub("[\n\t]"; " "))[0:110])]
        | @tsv'
}

# ---------------------------------------------------------------------------
# modes
# ---------------------------------------------------------------------------

# Live sessions, sorted by state then recency, so whatever is waiting on you
# floats to the top.
emit_active() {
    local id state cwd model branch updated pid pane name file rank icon label age
    while IFS=$'\t' read -r id state cwd model branch updated pid pane name file; do
        alive "$pid" || state=dormant
        case $state in
            blocked) rank=0 ;;
            working) rank=1 ;;
            idle) rank=2 ;;
            *) rank=3 ;;
        esac
        icon_for "$state"
        icon=$REPLY
        fmt_age "$((now - updated))"
        age=$REPLY
        label=$name
        [ "$label" = - ] && label=${cwd##*/}
        [ "$branch" = - ] || branch="@$branch"
        printf '%s\t%s %-20.20s %-32.32s %-16.16s %-14.14s %4s\t%s\t%s\t%s\n' \
            "$rank$((9999999999 - updated))" \
            "$icon" "$label" "${cwd/#$HOME/\~}" "${model##*/}" "$branch" "$age" \
            "$id" "$file" "$pane"
    done < <(live_rows) | sort | cut -f2-
}

# Sessions on disk (newest first), annotated with live state where pi-presence
# knows about them. `project` restricts to $PWD's session dir.
emit_files() {
    local scope=$1 limit=$2
    local -A st=() pane=() mt=()
    local id state pid p rest

    while IFS=$'\t' read -r id state _ _ _ _ pid p rest; do
        alive "$pid" || state=dormant
        st[$id]=$state
        pane[$id]=$p
    done < <(live_rows)

    local roots=() root
    if [ "$scope" = project ]; then
        mapfile -t roots < <(session_dir_for "$PWD")
        if [ ${#roots[@]} -eq 0 ]; then
            printf 'no sessions recorded for %s\t-\t-\t-\n' "${PWD/#$HOME/\~}"
            return
        fi
    else
        while read -r root; do
            [ -d "$root/sessions" ] && roots+=("$root/sessions")
        done < <(agent_dirs)
    fi

    # Two passes over the same ordered list: collect mtimes, then summarize.
    # `summarize` preserves input order, so the join is positional and the
    # newest-first ordering survives without a second sort.
    local mtime file cwd name prompt sid icon label age
    while IFS=$'\t' read -r mtime file; do mt[$file]=$mtime; done < <(session_files "$limit" "${roots[@]}")

    while IFS=$'\t' read -r file cwd name prompt; do
        sid=${file##*/}
        sid=${sid%.jsonl}
        sid=${sid#*_}
        icon_for "${st[$sid]:-dormant}"
        icon=$REPLY
        fmt_age "$((now - ${mt[$file]:-$now}))"
        age=$REPLY
        label=$name
        [ "$label" = - ] && label=$prompt
        printf '%s %-44.44s %-28.28s %4s\t%s\t%s\t%s\n' \
            "$icon" "$label" "${cwd/#$HOME/\~}" "$age" \
            "$sid" "$file" "${pane[$sid]:--}"
    done < <(session_files "$limit" "${roots[@]}" | cut -f2- | summarize)
}

case $mode in
    active) emit_active ;;
    project) emit_files project 200 ;;
    recent) emit_files all 150 ;;
    *)
        printf 'unknown mode: %s\n' "$mode" >&2
        exit 2
        ;;
esac
