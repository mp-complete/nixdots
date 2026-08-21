#!/usr/bin/env bash
# Television pickers for kitty's leader-mode bindings (desktop/apps/kitty.nix).
#
# The tmux side of this (shell/tmux.nix) can put the whole pipeline inline in a
# `display-popup -E` because tmux hands the command to `/bin/sh`. kitty does
# not: `launch` splits its command line with a shlex and execs it directly, so
# neither the `--keybindings='enter="actions:edit"'` quoting nor the
# `$(...)`-capture-then-act channels survive being written in kitty.conf. Every
# picker that needs either therefore goes through this dispatcher.
#
# `tv` is deliberately resolved from PATH rather than pinned: the kitty wrapper
# appends the wrapped television to its own PATH as a floor (see
# `runtimePkgs` in desktop/apps/kitty.nix), so a globally-installed one still
# wins, exactly as in the tmux wrapper.

case "${1:-}" in
    # Files under the launching window's cwd, opened in $EDITOR. Enter is
    # rebound here rather than in the channel because `files` is also tv's
    # ctrl-t fallback channel in fish (shell/television.nix), where printing
    # the path to the prompt is the correct behaviour.
    files)
        exec tv files --keybindings='enter="actions:edit"'
        ;;

    # Ripgrep the cwd; Enter opens $EDITOR at the matching line.
    text)
        exec tv text
        ;;

    # This flake, from anywhere (custom `nixdots` channel).
    nixdots)
        exec tv nixdots
        ;;

    # Enter checks out, ctrl-d deletes, ctrl-m merges, ctrl-r rebases onto.
    git-branch)
        exec tv git-branch
        ;;

    # Git log browser. The channel's own actions are ctrl-y cherry-pick /
    # ctrl-r revert / ctrl-o checkout; Enter puts the sha on the clipboard so
    # it can be pasted into whatever command prompted the lookup. `kitten
    # clipboard` is used instead of the tmux paste buffer -- it writes OSC 52
    # to the controlling terminal, so unlike `kitten @ set-clipboard` it needs
    # no `allow_remote_control`.
    git-log)
        sha=$(tv git-log) || exit 0
        [ -n "$sha" ] || exit 0
        printf '%s' "$sha" | kitten clipboard
        ;;

    # Every pi session, live ones first (ctrl-s cycles to this project's and to
    # all recent sessions). The channel prints a session id by default so that
    # `pi --session (tv pi-sessions)` composes; its alt-s "switch" action is
    # tmux-only (it shells out to `tmux switch-client`, see
    # modules/ai/_pi-sessions/switch.bash), so under kitty the printed id is
    # consumed here instead: the picker runs in a fresh tab and, on Enter,
    # `exec`s pi over itself in that same tab. Cancelling closes the tab.
    pi-sessions)
        id=$(tv pi-sessions) || exit 0
        [ -n "$id" ] || exit 0
        exec pi --session "$id"
        ;;

    *)
        echo "usage: kitty-tv {files|text|nixdots|git-branch|git-log|pi-sessions}" >&2
        exit 2
        ;;
esac
