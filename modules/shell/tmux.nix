{ config, ... }:
let
  # The flake-parts `config`, captured before the wrapper module below shadows
  # the name with its own `config`.
  flakeCfg = config;
in
{
  flake.wrappers.tmux =
    {
      pkgs,
      wlib,
      config,
      ...
    }:
    {
      imports = [ wlib.wrapperModules.tmux ];
      package = pkgs.tmux;

      # Self-contained: `run-shell "sesh last"` and the tv popups run with the
      # tmux *server's* PATH, not a login shell's. runtimePkgs is appended to
      # PATH, so the globally-installed sesh (shell/sesh.nix) and tv
      # (shell/television.nix) still win -- this is only the floor so the
      # wrapper never hard-depends on either being present. jq backs the
      # `worktrunk` channel's source command.
      #
      # The *wrapped* television is used deliberately: `pkgs.television` on its
      # own has no config, no channels and no theme, so every `tv <channel>`
      # binding below would fail against it. The floor omits the `worktrunk`
      # channel, which the `dev` bucket contributes at install time -- as does
      # `wt` itself, so `prefix C-w` already depends on that bucket either way.
      runtimePkgs = [
        pkgs.jq
        pkgs.sesh
        (flakeCfg.flake.wrappers.television.wrap { inherit pkgs; })
      ];

      prefix = "C-a";
      sourceSensible = true;
      mouse = true;
      vimVisualKeys = true;
      escapeTime = 0;
      historyLimit = 50000;
      baseIndex = 1;
      paneBaseIndex = 1;
      terminal = "tmux-256color";
      terminalOverrides = "*:Tc";
      modeKeys = "vi";

      plugins = with pkgs.tmuxPlugins; [
        { plugin = yank; }
        { plugin = pain-control; }
        { plugin = extrakto; }
        { plugin = tmux-fzf; }
        { plugin = fzf-tmux-url; }
        {
          plugin = catppuccin;
          configBefore = ''
            set -g @catppuccin_flavour 'macchiato'
            set -g @catppuccin_window_status_style 'rounded'

            # Truncate long session names with an ellipsis so they don't
            # eat the centered window list. `=/N/...` keeps the first N
            # characters and appends "…" when the name is longer.
            set -g @catppuccin_session_text '#{=/20/…:session_name}'

            # Catppuccin's default window tabs show `#T` (pane_title),
            # which apps like copilot-cli set to whatever they please via
            # OSC escapes (e.g. the user's first chat message). Use `#W`
            # (window_name) instead -- that's driven by
            # `automatic-rename-format` below and stays short.
            set -g @catppuccin_window_text ' #W'
            set -g @catppuccin_window_current_text ' #W'
          '';
        }
      ];

      # NOTE: there is deliberately no `configBefore`. The wrapper emits, in
      # order: configBefore -> each plugin's `run-shell` -> configAfter. A
      # non-backgrounded `run-shell` blocks tmux's command queue until the
      # script exits, so plugin bindings land *between* the two blocks and
      # silently overwrite anything configBefore bound. pain-control binds
      # h/j/k/l, C-h/C-j/C-k/C-l, H/J/K/L, | \ - _, " % and c -- which is how
      # `bind L run-shell "sesh last"` came to be dead code (pain-control
      # rebinds L to resize-pane -R). Everything custom therefore lives in
      # configAfter, where it reliably wins.
      configAfter = ''
        # Re-bind prefix-a to send-prefix so it still reaches the inner app
        bind -N "Send the prefix key through to the application" a send-prefix

        # Quick config reload (path of the wrapper-generated tmux.conf)
        bind R source-file ${config.constructFiles.generatedConfig.path} \; display-message "tmux config reloaded"

        # Split panes in the current working directory. pain-control binds
        # these identically; kept so the behaviour is stated here rather than
        # inherited silently from a plugin.
        bind '"' split-window -v -c "#{pane_current_path}"
        bind '%' split-window -h -c "#{pane_current_path}"
        bind c new-window -c "#{pane_current_path}"

        # Easier window swap (also bound by pain-control, to the same thing)
        bind -r "<" swap-window -d -t -1
        bind -r ">" swap-window -d -t +1

        # Copy-mode bindings (vi-style)
        bind -T copy-mode-vi 'C-v' send -X rectangle-toggle
        bind -T copy-mode-vi 'Escape' send -X cancel

        # Yazi file manager in a floating popup (mirrors zellij's Alt-g/Alt-c pattern)
        bind y display-popup -E -d "#{pane_current_path}" -w 90% -h 90% ${pkgs.yazi}

        # Lazygit in a floating popup, opened in the focused pane's CWD
        bind g display-popup -E -d "#{pane_current_path}" -w 90% -h 90% ${pkgs.lazygit}/bin/lazygit

        # Alt-backtick (no prefix): "quake" popup -- a throwaway shell in the
        # focused pane's CWD, for the one-off commands that would otherwise
        # cost a whole new window. `-E` closes the popup as soon as the shell
        # exits, so C-d/`exit` dismisses it and nothing survives. No command is
        # given, so tmux runs `default-shell` (fish, via the login shell).
        # `-T` puts the directory in the popup's border so it's obvious where
        # the shell landed; `#{b:...}` keeps it to the basename.
        bind -N "quake-style shell popup (cwd)" -n 'M-`' display-popup -E \
          -d "#{pane_current_path}" \
          -T " #{b:pane_current_path} " \
          -w 80% -h 80%

        # Alt-p (no prefix): pi in a new window, in the focused pane's CWD.
        # `pi` is resolved from PATH rather than pinned to a store path
        # because which wrapper is installed differs per host (pi-desktop vs
        # pi-wsl, see modules/ai/pi.nix), so the tmux wrapper must not depend
        # on either. automatic-rename-format labels the window `pi`.
        bind -N "open pi in a new window (cwd)" -n M-p new-window -c "#{pane_current_path}" pi

        # --- television (tv) pickers ------------------------------------
        #
        # `display-popup -E` closes the popup as soon as the command exits.
        # Channels whose Enter action uses `mode = "execute"` act on the
        # selection themselves, so unlike the `gum filter` popups these
        # replace, there is no `"$(...)"` capture and no shell quoting to get
        # wrong. Channels that only *print* their selection would close the
        # popup having done nothing, so those get an explicit Enter binding
        # via `--keybindings` at the call site.
        #
        # Sizes are uniform at 80% -- tv's landscape layout gives half the
        # width to the preview panel, so the 40%-wide gum popups were too
        # narrow to read.

        # Sessions: tmux sessions + zoxide dirs + configured projects.
        # ctrl-s cycles All/Tmux/Configs/Zoxide, ctrl-d kills a session.
        bind b display-popup -E -w 80% -h 80% "tv sesh"

        # Last session. With `detach-on-destroy off` (below) tmux's own
        # last-session breaks once a detached session is destroyed, so route
        # it through sesh. This is the binding pain-control used to clobber.
        bind -N "last session (via sesh)" L run-shell "sesh last"

        # Worktrunk worktrees -> sesh session at the worktree path. Replaces
        # a `wt list | jq | gum filter` pipeline whose `{{ worktree_path }}`
        # placeholder needed three levels of escaping.
        bind C-w display-popup -E -w 80% -h 80% "tv worktrunk"

        # Every window in every session; Enter switches this client to it.
        # Depends on the tmux-windows channel redefined in
        # shell/television.nix -- the upstream one does nothing on Enter.
        bind w display-popup -E -w 80% -h 80% "tv tmux-windows"

        # Files under the focused pane's CWD, opened in $EDITOR. Enter is
        # bound here rather than in the channel because `files` is also tv's
        # ctrl-t fallback channel in fish (shell/television.nix), where
        # printing the path to the prompt is the correct behaviour.
        bind f display-popup -E -d "#{pane_current_path}" -w 80% -h 80% "tv files --keybindings='enter=\"actions:edit\"'"

        # Ripgrep the pane's CWD; Enter opens $EDITOR at the matching line.
        bind / display-popup -E -d "#{pane_current_path}" -w 80% -h 80% "tv text"

        # This flake, from anywhere (custom `nixdots` channel).
        bind e display-popup -E -w 80% -h 80% "tv nixdots"

        # Git branches: Enter checks out, ctrl-d deletes, ctrl-m merges,
        # ctrl-r rebases onto.
        bind C-g display-popup -E -d "#{pane_current_path}" -w 80% -h 80% "tv git-branch"

        # Git log browser. The channel's own actions are ctrl-y cherry-pick /
        # ctrl-r revert / ctrl-o checkout; Enter drops the sha into the tmux
        # paste buffer so it can be pasted into whatever command prompted the
        # lookup. Single-quoted on purpose: tmux expands $name inside double
        # quotes, which would eat $sha before the popup's shell ever sees it.
        bind C-f display-popup -E -d "#{pane_current_path}" -w 80% -h 80% 'sha=$(tv git-log) && [ -n "$sha" ] && tmux set-buffer -- "$sha"'

        # ----------------------------------------------------------------

        # prefix-x kills the pane without the y/n prompt.
        bind x kill-pane

        bind C-n display-popup -E -w 20% "wt switch --no-cd -x \'sesh connect {{ worktree_path }}\' -c \"$(
          gum input --placeholder 'New branch name' --height 10
        )\""

        # smart-splits.nvim integration: seamless nav + resize between
        # tmux panes and nvim splits. Forwards C-hjkl / M-hjkl to nvim
        # when the focused pane is running (n)vim; otherwise selects or
        # resizes the tmux pane directly.
        is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|l?n?vim?x?|fzf)(diff)?$'"
        bind-key -n C-h if-shell "$is_vim" 'send-keys C-h' 'select-pane -L'
        bind-key -n C-j if-shell "$is_vim" 'send-keys C-j' 'select-pane -D'
        bind-key -n C-k if-shell "$is_vim" 'send-keys C-k' 'select-pane -U'
        bind-key -n C-l if-shell "$is_vim" 'send-keys C-l' 'select-pane -R'

        bind-key -n M-h if-shell "$is_vim" 'send-keys M-h' 'resize-pane -L 3'
        bind-key -n M-j if-shell "$is_vim" 'send-keys M-j' 'resize-pane -D 3'
        bind-key -n M-k if-shell "$is_vim" 'send-keys M-k' 'resize-pane -U 3'
        bind-key -n M-l if-shell "$is_vim" 'send-keys M-l' 'resize-pane -R 3'

        bind-key -T copy-mode-vi C-h select-pane -L
        bind-key -T copy-mode-vi C-j select-pane -D
        bind-key -T copy-mode-vi C-k select-pane -U
        bind-key -T copy-mode-vi C-l select-pane -R

        # Enable CSI u / extended key reporting so modifiers like
        # Ctrl/Shift/Alt on otherwise-ambiguous keys (e.g. C-Enter,
        # S-Enter, C-/) reach the inner application. `always` makes tmux
        # emit extended sequences unconditionally; pair it with
        # advertising the `extkeys` terminal feature to the outer term.
        set -s extended-keys always
        set -as terminal-features 'xterm*:extkeys'

        # Emit CSI u (fixterms / kitty-style) sequences rather than the
        # legacy xterm modifyOtherKeys format. Tools like pi parse the
        # csi-u form to disambiguate modified keys reliably.
        set -g extended-keys-format csi-u

        # sesh workflow: keep the client attached when a session it just left is
        # destroyed, so `sesh` / `sesh last` can switch to another session
        # instead of dropping you out of tmux entirely.
        set -g detach-on-destroy off

        # Status bar position
        set -g status-position top

        # Give the status-left/right segments enough room to render the
        # session name, prefix indicator, etc. without truncation. The
        # tmux defaults (10 / 40) chop long session names and squeeze
        # the centered window list off the bar.
        set -g status-left-length 80
        set -g status-right-length 120

        # Don't let apps (copilot-cli, ssh, etc.) rename windows via OSC
        # title escapes -- they tend to dump multi-line prompts in there
        # and blow up the status bar.
        set -g allow-rename off
        set -g automatic-rename on
        set -g automatic-rename-format '#{b:pane_current_command}'

        # Keep pane border titles short for the same reason.
        set -g pane-border-format '#{pane_index} #{b:pane_current_command}'
      '';
    };

  # Install the wrapped tmux into the core shell so it lands on PATH (same place
  # as yazi). Without this the `flake.wrappers.tmux` above is only a registry
  # entry (`nix run .#tmux`) and never enters any host's environment. Uses the
  # outer flake-parts `config`, mirroring how worktrunk installs its wrapper.
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.packages = [ (config.flake.wrappers.tmux.wrap { inherit pkgs; }) ];
    };
}
