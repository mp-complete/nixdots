{ config, ... }:
let
  # The flake-parts `config`, captured before the wrapper module below shadows
  # the name with its own `config`.
  flakeCfg = config;
in
{
  # television (`tv`) -- https://alexpasmantier.github.io/television/
  #
  # A "Telescope.nvim for the terminal": one picker UI, many declarative data
  # sources. Each source is a *channel* -- a TOML file describing
  # `[source]` -> `[preview]` -> `[actions]`. Compare fzf (shell/tools.nix),
  # which is a primitive you glue workflows around by hand.
  #
  # Division of labour in this config (per
  # https://daviddwlee84.github.io/dotfiles/tools/tv-vs-fzf/):
  #
  #   atuin  -- ctrl-r, shell history (sync + directory/session filtering)
  #   fzf    -- alt-c (cd), `**<TAB>` completion, ctrl-alt-{f,l,s,p} + ctrl-v
  #             via the fzf-fish plugin (shell/fish.nix), and the plain file
  #             widget, relocated to ctrl-alt-t below
  #   tv     -- ctrl-t smart autocomplete (context-aware: the channel is
  #             picked from the command already on the prompt), plus every
  #             structured picker: `tv`, `tv git-log`, `tv sesh`, ...
  #
  # Packaged as a wrapper rather than via home-manager's `programs.television`
  # so the config, the channels and the theme all travel with the binary. That
  # matters because `tv` is invoked from tmux `display-popup`s (shell/tmux.nix),
  # which do not run a login shell and so cannot be relied on to have a
  # populated `~/.config/television`.
  flake.wrappers.television =
    {
      pkgs,
      lib,
      wlib,
      ...
    }:
    let
      # Upstream keeps the community channels in-tree, so linking them from
      # the source derivation pins them to exactly the revision the binary was
      # built from -- no `tv update-channels` fetch, no drift.
      cable = "${pkgs.television.src}/cable/unix";

      # Curated rather than "link the whole directory": upstream ships ~90
      # channels covering aws/brew/guix/pacman/launchd/snap and friends, none
      # of which exist here, and they would all show up in remote control
      # (ctrl-t inside tv) as dead entries.
      upstreamChannels = [
        # core
        "files"
        "text"
        "dirs"
        "env"
        "alias"
        "dotfiles"
        "zoxide"
        "recent-files"
        # git
        "git-branch"
        "git-diff"
        "git-files"
        "git-log"
        "git-reflog"
        "git-repos"
        "git-stash"
        "git-tags"
        "git-worktrees"
        # forge (programs.gh -- development/git.nix)
        "gh-prs"
        "gh-issues"
        # build/run
        "just-recipes"
        "make-targets"
        "npm-scripts"
        "docker-containers"
        "docker-images"
        # system
        "systemd-units"
        "journal"
        "ports"
        "procs"
        "ssh-hosts"
        "man-pages"
        # NB: `sesh`, `tmux-sessions` and `tmux-windows` are deliberately
        # absent -- the upstream versions are either unusable from inside tmux
        # or need extra actions, and are replaced by the definitions further
        # down (session management: shell/sesh.nix, shell/tmux.nix).
      ];

      # Backs the sesh channel's per-program actions (`alt-y` / `alt-p`).
      # Written as a script rather than inlined into the action's `command`
      # because the new/existing decision needs more than one shell statement.
      #
      # Everything runs through `tmux send-keys`, i.e. the program is typed
      # into the target session's shell. That resolves it against the *user's*
      # PATH rather than tv's or the tmux server's (which matters for `pi`,
      # since the binary is either pi-desktop or pi-wsl depending on the host),
      # and quitting the program leaves a usable prompt instead of a window
      # that vanishes.
      seshOpen = pkgs.writeShellScript "sesh-open" ''
        # usage: sesh-open <program> <sesh entry>
        prog=$1
        entry=$2

        if [ -n "''${TMUX:-}" ]; then
            # Which sessions existed *before* connecting. `tmux has-session
            # -t="$entry"` cannot answer this: for a zoxide/dir entry the
            # entry is a path while sesh derives the session name from it
            # (connector/dir.go -> namer), so `~/src/foo` becomes `foo`. The
            # snapshot avoids reimplementing that naming.
            before=$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)

            sesh connect "$entry" || exit $?

            # `sesh connect` inside tmux is `switch-client`, so the current
            # client is now on the target session -- true even from inside a
            # `display-popup`, and the value updates synchronously.
            session=$(tmux display-message -p '#{client_session}')

            if printf '%s\n' "$before" | grep -qxF -- "$session"; then
                # Session already existed: give the program its own window.
                # Target the returned @id, not "$session:$prog" -- window
                # names are not unique, and a repeat press would otherwise
                # send keys to the *previous* window of the same name.
                target=$(tmux new-window -t "$session" -n "$prog" -P -F '#{window_id}')
            else
                # Brand new session: type into the shell sesh just started,
                # which is exactly what `sesh connect -c` does internally.
                target=$session
            fi

            exec tmux send-keys -t "$target" "$prog" Enter
        fi

        # Outside tmux there is no client to interrogate and `sesh connect`
        # *attaches* (blocking), so any window work has to happen first. Only
        # exact session names can be resolved here; anything else falls back to
        # sesh's own startup command, which fires for new sessions only.
        if tmux has-session -t="$entry" 2>/dev/null; then
            target=$(tmux new-window -t "$entry" -n "$prog" -P -F '#{window_id}')
            tmux send-keys -t "$target" "$prog" Enter
            exec sesh connect "$entry"
        fi
        exec sesh connect -c "$prog" "$entry"
      '';

      # Catppuccin Macchiato -- matches kitty (desktop/apps/kitty.nix), yazi
      # (shell/yazi.nix) and rofi (desktop/apps/rofi.nix). tv ships a builtin
      # `catppuccin` theme but it is the Mocha variant.
      macchiato = {
        base = "#24273a";
        text = "#cad3f5";
        overlay0 = "#6e738d";
        surface0 = "#363a4f";
        blue = "#8aadf4";
        lavender = "#b7bdf8";
        mauve = "#c6a0f6";
        red = "#ed8796";
        peach = "#f5a97f";
        yellow = "#eed49f";
        green = "#a6da95";
        pink = "#f5bde6";
      };
    in
    {
      imports = [ wlib.wrapperModules.television ];
      package = pkgs.television;

      # `tv` runs every `[source]`/`[preview]`/`[actions]` command through a
      # shell, so the tools those commands name have to be reachable no matter
      # how tv was launched -- including from a tmux popup, which inherits the
      # tmux *server's* environment rather than a login shell's.
      runtimePkgs = with pkgs; [
        fd
        bat
        ripgrep
        git
        jq
        eza
        sesh
        # For the tmux-* channels and `seshOpen` above. Appended to PATH, so a
        # tmux already on PATH (the popup case) still wins.
        tmux
      ];

      settings = {
        tick_rate = 50;
        default_channel = "files";
        history_size = 200;
        # Scope history navigation (ctrl-up/ctrl-down) to the current
        # channel; a global query history mixes unrelated pickers.
        global_history = false;

        ui = {
          ui_scale = 100;
          orientation = "landscape";
          theme = "catppuccin-macchiato";
          use_nerd_font_icons = true;
          input_bar = {
            position = "top";
            border_type = "rounded";
          };
          results_panel.border_type = "rounded";
          preview_panel = {
            size = 50;
            scrollbar = true;
            border_type = "rounded";
          };
          help_panel.show_categories = true;
          remote_control.show_channel_descriptions = true;
        };

        # ctrl-t on an empty prompt falls back to `files`; otherwise the
        # command already typed selects the channel. This is the one thing
        # fzf cannot do, and the reason tv gets ctrl-t here.
        shell_integration = {
          fallback_channel = "files";
          channel_triggers = {
            "alias" = [
              "alias"
              "unalias"
            ];
            "env" = [
              "export"
              "unset"
              "echo $"
            ];
            "dirs" = [
              "cd"
              "ls"
              "eza"
              "rmdir"
              "z"
            ];
            "files" = [
              "cat"
              "bat"
              "less"
              "head"
              "tail"
              "nvim"
              "vim"
              "cp"
              "mv"
              "rm"
              "touch"
              "chmod"
              "chown"
              "ln"
              "tar"
              "zip"
              "unzip"
              "glow"
            ];
            "git-diff" = [
              "git add"
              "git restore"
            ];
            "git-branch" = [
              "git checkout"
              "git switch"
              "git branch"
              "git merge"
              "git rebase"
              "git pull"
              "git push"
            ];
            "git-log" = [
              "git log"
              "git show"
              "git cherry-pick"
              "git revert"
            ];
            "git-stash" = [ "git stash" ];
            "git-worktrees" = [ "git worktree" ];
            "git-repos" = [
              "git clone"
              "code"
            ];
            "gh-prs" = [ "gh pr" ];
            "gh-issues" = [ "gh issue" ];
            "just-recipes" = [ "just" ];
            "npm-scripts" = [
              "npm run"
              "yarn"
              "pnpm run"
            ];
            "docker-images" = [ "docker run" ];
            "docker-containers" = [
              "docker exec"
              "docker logs"
              "docker stop"
              "docker rm"
            ];
            "systemd-units" = [
              "systemctl"
              "journalctl"
            ];
            "ssh-hosts" = [
              "ssh"
              "scp"
              "sftp"
            ];
            "man-pages" = [ "man" ];
            "sesh" = [ "sesh" ];
            # fish abbreviations (shell/fish.nix) -- see the `abbrs` channel.
            "abbrs" = [ "abbr" ];
            "nixdots" = [
              "nix"
              "nh"
              "nixos-rebuild"
            ];
          };
          keybindings = {
            smart_autocomplete = "ctrl-t";
            # tv still writes a ctrl-r binding when its snippet is sourced;
            # the fish block below hands the key back to atuin.
            command_history = "ctrl-r";
          };
        };
      };

      # `channels` accepts either an absolute path (linked verbatim) or an
      # attrset (rendered to TOML), which is why the vendored upstream set
      # collapses to a one-line `genAttrs`.
      channels = lib.genAttrs upstreamChannels (name: "${cable}/${name}.toml") // {
        # This flake's checkout. `$NH_FLAKE` is exported globally by
        # `programs.nh` (system/nix-tools.nix), so the channel resolves the
        # right tree per host -- `~/.config/nixdots` on hilbert/general2 but
        # `~/.config/nixos` on the `nixos` host -- without this flake-level
        # wrapper needing an `osConfig`. Deliberately written without
        # `${VAR:-default}`: tv runs source commands under `$SHELL`
        # (`Shell::from_env()`), and that syntax is not valid in fish.
        nixdots = {
          metadata = {
            name = "nixdots";
            description = "Files in this flake ($NH_FLAKE)";
            requirements = [
              "fd"
              "bat"
            ];
          };
          # `cd` first so entries are flake-relative and the results panel
          # stays readable; the preview/action re-absolutise them.
          source = {
            command = [
              {
                name = "Nix";
                run = "cd \"$NH_FLAKE\" && fd -t f -e nix";
              }
              {
                name = "All";
                run = "cd \"$NH_FLAKE\" && fd -t f";
              }
              {
                name = "Modules";
                run = "cd \"$NH_FLAKE/modules\" && fd -t f -e nix";
              }
            ];
          };
          preview = {
            command = "bat -n --color=always \"$NH_FLAKE/{}\"";
            env.BAT_THEME = "ansi";
          };
          keybindings.enter = "actions:edit";
          actions.edit = {
            description = "Open the selected file in $EDITOR";
            command = "\${EDITOR:-vim} \"$NH_FLAKE/{}\"";
            shell = "bash";
            mode = "execute";
          };
        };

        # Discovery surface for abbreviations. fish exposes them through
        # tab-completion descriptions (`n<TAB>` -> "nos  Abbreviation: nh os
        # switch") and `abbr --show`, and nothing else: `type nos` reports
        # "Could not find", `functions -q` is blind to them, `alias` lists a
        # different namespace, and `fish_config browse` has no page for them.
        # That matters more since `programs.fish.preferAbbrs`
        # (shell/fish.nix) moved most aliases into this namespace.
        #
        # Reachable from `abbr <ctrl-t>` (see `channel_triggers` above) or
        # from remote control.
        abbrs = {
          metadata = {
            name = "abbrs";
            description = "fish abbreviations and what they expand to";
            requirements = [ "fish" ];
          };
          source = {
            # `fish -ic`, not a bare command: abbreviations are defined in
            # interactiveShellInit, and tv runs source commands under $SHELL,
            # which here is bash -- fish is the *interactive* shell only
            # (shell/fish.nix). stderr is dropped because an interactive fish
            # on a pipe warns about unanswered terminal queries.
            #
            # `abbr --list` yields names only and `abbr --show` whole
            # `abbr --add -- name 'expansion'` lines, so the expansion is
            # recovered per name. \Q..\E stops names like `!` being read as
            # regex, and `string trim -c \x27` strips the quotes `--show`
            # adds without putting a literal ' inside the outer sh string.
            command = ''fish -ic 'for a in (abbr --list); printf "%s\t%s\n" $a (string trim -c \x27 -- (abbr --show | string match -r -- "-- \Q$a\E (.*)\$")[2]); end' 2>/dev/null'';
            display = "{split:	:0} → {split:	:1}";
            # The name, not the expansion: the point of the `abbr` trigger is
            # to complete `abbr <name>`, and typing the name at a prompt
            # expands it anyway.
            output = "{split:	:0}";
          };
          # Long expansions get truncated in the results panel.
          preview.command = "fish -ic 'abbr --show' 2>/dev/null | grep -F -- ' {split:	:0} '";
          ui.preview_panel.size = 30;
        };

        # Vendored from upstream's `cable/unix/sesh.toml` (hence the absence
        # of "sesh" from `upstreamChannels`) so that extra actions can be
        # bolted on. There is no lighter way to do that: `tv`'s `-k` /
        # `--keybindings` flag only rebinds *existing* actions, and there is
        # no `--actions`, so the whole prototype has to live here. Keep in
        # sync with upstream when the television input is bumped.
        #
        # Reached via `prefix b` (shell/tmux.nix) as well as plain `tv sesh`.
        sesh =
          let
            # Upstream's template: `sesh list --icons` prefixes each line with
            # a coloured nerd-font glyph, so drop column 0 and the ANSI codes.
            entry = "{strip_ansi|split: :1..|join: }";

            # `sesh connect -c CMD` would have been the whole implementation,
            # but it is gated on the session being *new* (connector/tmux.go:
            # `if connection.New { NewSession(); SendKeys(CMD) }`), so picking
            # a session that already exists would silently do nothing. The
            # helper keeps that behaviour for new sessions and opens a fresh
            # window for existing ones.
            openWith = program: {
              description = "Connect, opening ${program} (new window if the session exists)";
              command = "${seshOpen} ${program} '${entry}'";
              mode = "execute";
            };
          in
          {
            metadata = {
              name = "sesh";
              description = "Session manager integrating tmux sessions, zoxide directories, and config paths";
              requirements = [
                "sesh"
                "fd"
              ];
            };
            # ctrl-s cycles these modes.
            source = {
              command = [
                {
                  name = "All";
                  run = "sesh list --icons";
                }
                {
                  name = "Tmux";
                  run = "sesh list -t --icons";
                }
                {
                  name = "Configs";
                  run = "sesh list -c --icons";
                }
                {
                  name = "Zoxide";
                  run = "sesh list -z --icons";
                }
                {
                  name = "Directories";
                  run = "fd -H -d 2 -t d -E .Trash . ~";
                }
              ];
              ansi = true;
              frecency = false; # handled by sesh
              no_sort = true; # handled by sesh
              output = entry;
            };
            preview.command = "sesh preview '${entry}'";
            keybindings = {
              enter = "actions:connect";
              ctrl-d = [
                "actions:kill_session"
                "reload_source"
              ];
              # alt- rather than ctrl-: tv's defaults already claim ctrl-y
              # (copy_entry_to_clipboard) and ctrl-p (select_prev_entry).
              alt-y = "actions:connect_yazi";
              alt-p = "actions:connect_pi";
            };
            actions = {
              connect = {
                description = "Connect to selected session";
                command = "sesh connect '${entry}'";
                mode = "execute";
              };
              kill_session = {
                description = "Kill selected tmux session (press Ctrl+r to reload)";
                command = "tmux kill-session -t '${entry}'";
                mode = "fork";
              };
              connect_yazi = openWith "yazi";
              connect_pi = openWith "pi";
            };
          };

        # tmux session / window pickers, replacing the upstream channels of
        # the same name (see `upstreamChannels` above). The vendored ones are
        # broken for the way they are actually used here -- from a
        # `display-popup` inside a running tmux (shell/tmux.nix):
        #
        #   * Neither defines `[keybindings] enter`, so Enter merely prints
        #     the selection on stdout. In a `display-popup -E` that output
        #     goes nowhere and the popup just closes, having done nothing.
        #     Their `[actions]` are reachable only via the action picker.
        #   * `tmux-sessions` attaches with `attach-session`, which refuses
        #     to nest while $TMUX is set.
        #   * `tmux-windows` uses `select-window`, which sets the *target*
        #     session's active window but leaves this client where it was.
        #     Verified: with a client on `alpha:a1`, `select-window -t
        #     beta:2` left it on `alpha:a1`; `switch-client -t beta:2`
        #     moved it.
        #
        # `switch-client -t 'session:index'` does both hops at once and is
        # safe from inside a popup, so both channels below use it.
        #
        # The `\t` sequences are real tab characters (Nix "" strings expand
        # them, and the TOML writer escapes them back), so the format
        # string, the display/output templates and the preview all agree on
        # the separator. Tabs rather than spaces because session and window
        # names may legitimately contain spaces.
        tmux-sessions = {
          metadata = {
            name = "tmux-sessions";
            description = "Switch between tmux sessions";
            requirements = [ "tmux" ];
          };
          source = {
            command = "tmux list-sessions -F '#{session_name}\t#{session_windows} windows\t#{session_created_string}'";
            display = "{split:\t:0} ({split:\t:1})";
            output = "{split:\t:0}";
          };
          preview.command = "tmux capture-pane -p -t '{split:\t:0}' 2>/dev/null || echo 'No preview available'";
          keybindings = {
            enter = "actions:switch";
            ctrl-d = [
              "actions:kill"
              "reload_source"
            ];
          };
          actions = {
            switch = {
              description = "Switch this client to the selected session";
              command = "tmux switch-client -t '{split:\t:0}'";
              mode = "execute";
            };
            kill = {
              description = "Kill the selected session";
              command = "tmux kill-session -t '{split:\t:0}'";
              mode = "fork";
            };
          };
        };

        tmux-windows = {
          metadata = {
            name = "tmux-windows";
            description = "Jump to any window in any tmux session";
            requirements = [ "tmux" ];
          };
          source = {
            command = "tmux list-windows -a -F '#{session_name}:#{window_index}\t#{window_name}\t#{pane_current_command}'";
            display = "{split:\t:0} - {split:\t:1} ({split:\t:2})";
            output = "{split:\t:0}";
          };
          preview.command = "tmux capture-pane -p -t '{split:\t:0}' 2>/dev/null || echo 'No preview available'";
          keybindings = {
            enter = "actions:switch";
            ctrl-d = [
              "actions:kill"
              "reload_source"
            ];
          };
          actions = {
            switch = {
              description = "Switch this client to the selected window";
              command = "tmux switch-client -t '{split:\t:0}'";
              mode = "execute";
            };
            kill = {
              description = "Kill the selected window";
              command = "tmux kill-window -t '{split:\t:0}'";
              mode = "fork";
            };
          };
        };
      };

      # `tv` has no themes flag: a theme named in `settings.ui.theme` is
      # resolved only as `<config dir>/themes/<name>.toml`, and missing files
      # fall back to the builtin/default theme *silently*. The wrapper module
      # handles that by exporting `TELEVISION_CONFIG` whenever `themes` is
      # non-empty -- see the fix this flake pins nix-wrapper-modules to.
      themes.catppuccin-macchiato = {
        background = macchiato.base;
        border_fg = macchiato.overlay0;
        text_fg = macchiato.text;
        dimmed_text_fg = macchiato.overlay0;

        input_text_fg = macchiato.red;
        result_count_fg = macchiato.red;

        result_name_fg = macchiato.blue;
        result_line_number_fg = macchiato.yellow;
        result_value_fg = macchiato.lavender;
        selection_fg = macchiato.green;
        selection_bg = macchiato.surface0;
        match_fg = macchiato.red;

        preview_title_fg = macchiato.peach;

        channel_mode_fg = macchiato.base;
        channel_mode_bg = macchiato.pink;
        remote_control_mode_fg = macchiato.base;
        remote_control_mode_bg = macchiato.green;
        action_picker_mode_fg = macchiato.base;
        action_picker_mode_bg = macchiato.mauve;
      };
    };

  flake.modules.homeManager.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.television.extraChannels = lib.mkOption {
        type = lib.types.attrsOf lib.types.raw;
        default = { };
        description = ''
          Extra `tv` channels merged into the wrapper at install time.

          `flake.wrappers` is evaluated once at the flake level, so a channel
          that should only exist on some hosts cannot be declared there. This
          option lets a home-manager bucket contribute one -- see the
          `worktrunk` channel in the `dev` bucket below.
        '';
      };

      config = {
        home.packages = [
          (flakeCfg.flake.wrappers.television.wrap {
            inherit pkgs;
            channels = config.television.extraChannels;
          })
        ];

        # Abbreviations only where `tv` actually costs keystrokes. Deliberately
        # *not* one per channel: `shell_integration.channel_triggers` above
        # already picks the channel from the command being typed (ctrl-t), and
        # sesh/tmux-windows have alt-b/alt-m, so `tvs`-style abbrs would be
        # dead weight. What is left over is ad-hoc mode and the two channels
        # with neither a trigger nor a key.
        programs.fish.shellAbbrs = {
          # Ad-hoc mode: no channel, just a command to fuzz over. The flags are
          # long and easy to misremember (`-p` is --preview-command, not
          # --preview), and `--set-cursor` drops the cursor inside the empty
          # quotes so the source command can be typed straight away.
          tvad = {
            setCursor = true;
            expansion = ''tv --source-command "%" --preview-command "bat -n --color=always {}"'';
          };
          # ripgrep over the current tree. Has a tmux popup (`prefix /`) but no
          # trigger, and at a prompt it is often wanted in a subdirectory.
          tvt = "tv text";
          # Channel discovery, the companion to the `abbrs` channel above.
          tvl = "tv list-channels";
        };

        programs.fish.interactiveShellInit = lib.mkAfter ''
          # television's fish integration, sourced by hand rather than via an
          # `enable*Integration` flag because the upstream snippet
          # unconditionally binds ctrl-t and ctrl-r. mkAfter (order 1500) puts
          # it after fzf's and atuin's init so the final keymap is explicit
          # rather than dependent on module evaluation order.
          source ${pkgs.television}/share/television/completion.fish

          # ctrl-t is now tv's smart autocomplete. Move fzf's plain file widget
          # to ctrl-alt-t rather than let it be silently shadowed; the fzf-fish
          # plugin's own bindings (ctrl-alt-f/l/s/p, ctrl-v) are untouched.
          if functions -q fzf-file-widget
              bind ctrl-alt-t fzf-file-widget
              if bind -M insert >/dev/null 2>&1
                  bind -M insert ctrl-alt-t fzf-file-widget
              end
          end

          # ctrl-r goes back to atuin. tv's `fish-history` channel reads
          # ~/.local/share/fish/fish_history directly, which would drop atuin's
          # sync plus the directory/session filter modes set in shell/tools.nix.
          if functions -q _atuin_search
              bind ctrl-r _atuin_search
              if bind -M insert >/dev/null 2>&1
                  bind -M insert ctrl-r _atuin_search
              end
          end

          # Action-shaped tv widgets. ctrl-t (smart autocomplete) *inserts* a
          # token; these instead run the channel's `enter` action and hand the
          # prompt back. Worth their own keys because neither channel has a
          # command prefix in `channel_triggers` that ctrl-t could key off --
          # you would have to type `sesh ` first, insert a name, then hit
          # enter.
          #
          # Fullscreen rather than `--inline`: `mode = "execute"` is
          # `cmd.exec()` in tv (television/utils/command.rs), so the process
          # *becomes* sesh/tmux and takes over the terminal, which would
          # otherwise be drawn over the prompt. Nothing is piped either --
          # execute-mode tv prints no selection of its own, and redirecting
          # stdout would push tv onto its `attach_to_tty` fallback, which
          # reopens /dev/tty and is documented upstream to break `tmux
          # attach`.
          function tv_exec --description "Run a tv channel for its enter action"
              tv $argv
              commandline -f repaint
          end

          # Shell twins of the tmux popups in shell/tmux.nix -- alt-b mirrors
          # `prefix b` (tv sesh) and alt-m mirrors `prefix w` (tv
          # tmux-windows), so the same pickers are one chord away without a
          # prefix key. alt- rather than ctrl-alt-: the latter belongs to
          # fzf-fish, while fish 4.8 ships no alt- presets at all.
          #
          # The `for mode in default insert` form is lifted from upstream's
          # completion.fish (sourced above), which binds both unconditionally;
          # `tmux-windows` only lists anything from inside tmux, which is the
          # only place it makes sense anyway.
          for mode in default insert
              bind --mode $mode alt-b "tv_exec sesh"
              bind --mode $mode alt-m "tv_exec tmux-windows"
          end
        '';
      };
    };

  # The worktrunk channel lives in the `dev` bucket because it shells out to
  # `wt`, which is only installed there (development/worktrunk.nix). It mirrors
  # the tmux `prefix C-w` popup, minus the gum/jq pipeline.
  flake.modules.homeManager.dev = {
    # `tv worktrunk` has neither a trigger nor a fish key (the tmux popup is
    # `prefix C-w`), and lives in this bucket because the channel does.
    programs.fish.shellAbbrs.tvw = "tv worktrunk";

    television.extraChannels.worktrunk = {
      metadata = {
        name = "worktrunk";
        description = "Git worktrees managed by worktrunk";
        requirements = [
          "wt"
          "jq"
          "sesh"
        ];
      };
      # `2>/dev/null` swallows worktrunk's json-schema deprecation notice.
      # If `[list] json-schema = 2` is ever adopted, revisit these jq paths.
      source = {
        command = "wt list --format json 2>/dev/null | jq -r '.[] | \"\\(.branch) \\(.path)\"'";
        display = "{split: :0}";
        output = "{split: :1}";
      };
      preview.command = "git -C '{split: :1}' log --oneline -20 --color=always; echo; git -C '{split: :1}' status --short";
      keybindings = {
        enter = "actions:connect";
        ctrl-e = "actions:edit";
      };
      actions = {
        connect = {
          description = "Attach a tmux session at the selected worktree";
          command = "sesh connect '{split: :1}'";
          mode = "execute";
        };
        edit = {
          description = "Open the selected worktree in $EDITOR";
          command = "\${EDITOR:-vim} '{split: :1}'";
          shell = "bash";
          mode = "execute";
        };
      };
    };
  };
}
