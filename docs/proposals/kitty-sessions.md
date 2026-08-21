# Proposal: kitty-native session switching

Status: proposal. Nothing in this document is implemented yet.

Follows on from the tmux→kitty port in `modules/desktop/apps/kitty.nix` (leader-mode
television pickers, `alt+\`` quake overlay, `alt+p` pi tab). That port deliberately
stopped at the three tmux pickers that cannot cross over — `prefix b` (sesh),
`prefix w` (tmux-windows) and `prefix C-w` (worktrunk) — because all three act by
shelling out to `tmux switch-client` / `new-window` / `send-keys`
(`modules/shell/television.nix:94-141`, `modules/shell/sesh.nix`). Outside a tmux
server they fall through to a branch that does nothing useful.

This document is about replacing the *capability*, not the implementation.

## What sesh actually gives us

Three things, which are worth separating because kitty covers them unevenly:

1. **Named projects.** `sesh`'s configured `session` entries — today exactly one, the
   flake checkout, whose path comes from `osConfig.programs.nh.flake` (`shell/sesh.nix`).
   Fixed set, declared in Nix.
2. **Ad-hoc directories.** Everything zoxide has ever seen. Unbounded, discovered at
   runtime, and the reason `tv sesh` has a `Zoxide` source mode at all.
3. **Attach-or-create + last-session.** `sesh connect` is idempotent, and `prefix L` →
   `sesh last` because `detach-on-destroy off` breaks tmux's own last-session.

## What kitty 0.48.2 already has

kitty's session system (`share/doc/kitty/html/_sources/sessions.rst.txt`) is a much
closer match than I expected:

- A **session file** is a plain text file of `cd` / `layout` / `launch` / `new_tab`
  directives. Extensions `.kitty-session`, `.kitty_session`, `.session`.
- `goto_session <path>` switches to one, creating it if not already active — that is
  `sesh connect`'s attach-or-create semantics, exactly.
- `goto_session <directory>` scans the directory for session files and shows kitty's
  **own interactive picker**. `--sort-by=alphabetical` or recency.
- `goto_session` with no argument lists every session known via a `goto_session`
  mapping; `--active-only` narrows to live ones — that is `tv sesh`'s All/Tmux split.
- `goto_session -1` is last-session. No `detach-on-destroy` caveat, so unlike tmux this
  needs no `sesh last` workaround.
- `close_session` closes every window in a session.
- `save_as_session --use-foreground-process --relocatable` dumps the current layout to
  a file, which is how a non-trivial session file should be authored in the first place.
- `{session_name}` is available in `tab_title_template`, so the status bar can show it.

Mapping to the three capabilities above:

| sesh capability | kitty equivalent | Gap |
|---|---|---|
| Named projects | `.kitty-session` files + `goto_session <dir>` | none — generate the files from Nix |
| Ad-hoc zoxide dirs | — | real gap; needs a generated session file per pick |
| Attach-or-create | `goto_session` | none |
| Last session | `goto_session -1` | none, and simpler than the tmux route |

## Proposed design

### Phase 1 — declared sessions, no new machinery

Generate a session file per named project into a store directory and point one leader
binding at it:

```nix
# modules/desktop/apps/kitty.nix (sketch)
sessions = pkgs.runCommand "kitty-sessions" { } ''
  mkdir -p $out
  cat > $out/nixdots.kitty-session <<EOF
  cd ${osConfig.programs.nh.flake}
  layout splits
  launch
  EOF
'';
# map --mode leader s goto_session ${sessions}
# map --mode leader - goto_session -1
```

Two caveats found while reading the docs, both of which want checking before this is
written:

- `osConfig` is not in scope in a `flake.wrappers.*` module — the kitty wrapper is
  instantiated from `flake.modules.nixos.desktop-core`, so the flake path has to be
  threaded in the same way `shell/sesh.nix` gets it, or read from `flakeCfg`.
- A store-path session directory is read-only, which is fine for `goto_session` but
  means `save_as_session` can never write back into it. Sessions authored by hand at
  runtime need a separate writable dir (`~/.local/share/kitty/sessions`) and a second
  binding.

This alone replaces `prefix b`'s "Configs" source mode, which is the part of `tv sesh`
that gets used most.

### Phase 2 — zoxide directories, via a scoped-remote-control picker

The gap is picking an arbitrary directory and getting a session for it. kitty has no
"session from a path" action, but `goto_session` accepts a path to a file that can be
written a moment earlier. So:

```
map --mode leader b launch --type=overlay --allow-remote-control kitty-sesh
```

`kitty-sesh` (a `writeShellApplication`, alongside `_kitty/tv.bash`) would:

1. run `tv sesh` restricted to its directory sources, capturing the selected path;
2. write `$XDG_CACHE_HOME/kitty/sessions/<slug>.kitty-session` containing `cd <path>`
   plus a default layout, unless it already exists;
3. `kitten @ action goto_session <that file>`.

The important detail is `launch --allow-remote-control`: per `remote-control.rst.txt`,
that grants remote control **to that one window only**, so this needs neither a global
`allow_remote_control` nor a `listen_on` socket. `remote_control_script` is the other
option and is arguably cleaner (it is documented as `--type=background
--allow-remote-control`), but it takes a script path rather than an interactive
program, so the picker still has to be an overlay.

Cache-dir session files also give `save_as_session` somewhere writable, which closes
the Phase 1 caveat.

### Phase 3 — pi sessions and worktrees

- **pi-sessions.** `modules/ai/_pi-sessions/switch.bash` correlates a live session to a
  pane via `$TMUX_PANE`, written by the pi-presence extension
  (`modules/ai/extensions/pi-presence.nix`). The kitty analogue is `$KITTY_WINDOW_ID`
  (plus `$KITTY_LISTEN_ON` if remote control is in play). That is a change to the
  *extension*, not just the script: it would have to record both, and `list.bash` would
  have to know which one is meaningful in the current terminal. Currently `leader+P`
  sidesteps this entirely by `exec`ing `pi --session <id>` in a fresh tab, which is
  strictly worse than switching to the already-running one but requires no changes.
- **worktrunk.** `wt switch --no-cd -x 'sesh connect {{ worktree_path }}'` is
  parameterised on the connect command, so the `-x` argument becomes the Phase 2
  `kitty-sesh` path instead. Cheap once Phase 2 exists; pointless before.

## What I would *not* port

- `prefix w` (tmux-windows). kitty's `kitty_mod+x` command palette and
  `select_tab`/`focus_visible_window` already cover cross-tab navigation, and a
  television channel over `kitten @ ls` would be a strictly worse version of the
  command palette.
- `sesh last` machinery. `goto_session -1` is native and has no destroyed-session edge
  case.

## Open questions

1. Is kitty actually being used *without* tmux inside it? If every kitty window runs
   tmux, all of this is redundant and the right answer is a `startup_session` that
   attaches tmux, plus nothing else. This decides whether Phase 2 is worth building.
2. Should the leader letters diverge? Phase 1 wants `leader+s`; tmux uses `prefix b`
   for the same concept. Consistency argues `b`.
3. `--allow-remote-control` on a picker window means the picker can drive kitty
   arbitrarily. That is a smaller blast radius than global `allow_remote_control`, but
   it is still worth stating explicitly in the module comment rather than leaving it
   implicit in a `launch` flag.
