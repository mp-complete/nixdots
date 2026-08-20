# pi-sessions-switch <tmux pane>
#
# Jump to the tmux pane a pi session is running in. Used by the `pi-sessions`
# channel's `switch` action (modules/ai/pi-sessions.nix), which passes the
# `terminal.tmuxPane` pi-presence recorded at session start.
#
# A pane id resolves all three hops on its own: `switch-client -t %26` moves
# the client to that pane's session *and* selects its window and pane (checked
# against tmux 3.5a -- a client on A:1.1 targeted at a pane in B:2.2 ends up on
# B:2.2, and B's active window follows).

pane=${1:--}

if [ -z "$pane" ] || [ "$pane" = - ]; then
    echo "pi-sessions: that session is not running inside tmux" >&2
    exit 1
fi

if ! tmux display-message -p -t "$pane" '#{pane_id}' >/dev/null 2>&1; then
    echo "pi-sessions: pane $pane is gone (the session outlived its terminal)" >&2
    exit 1
fi

# Outside tmux `switch-client` is a silent no-op -- it exits 0 having moved
# nothing, because there is no current client to move. Attaching takes the same
# pane target and lands on the right window.
if [ -n "${TMUX:-}" ]; then
    exec tmux switch-client -t "$pane"
fi
exec tmux attach-session -t "$pane"
