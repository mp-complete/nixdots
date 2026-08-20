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
      config,
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
        # session management (shell/sesh.nix, shell/tmux.nix)
        "sesh"
        # NB: `tmux-sessions` / `tmux-windows` are deliberately absent -- the
        # upstream versions are unusable from inside tmux and are replaced by
        # the definitions further down.
      ];

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

      # The wrapper module's `themes` option is a no-op as far as `tv` is
      # concerned: it writes `<out>/tv-themes/`, but tv has no themes flag and
      # resolves a theme name purely as
      # `get_config_dir()/themes/<name>.toml` (television/config/themes.rs),
      # falling back to the builtin/default theme *silently* when that file is
      # missing. So instead of `themes`, hand tv a real config directory via
      # `TELEVISION_CONFIG` -- the same trick desktop/apps/kitty.nix uses with
      # `KITTY_CONFIG_DIRECTORY`.
      #
      # `cable/.keep` is load-bearing: `ConfigEnv::init()` unconditionally runs
      # `create_dir_all(config_dir/cable)`, which fails hard against a
      # read-only store path when that subdirectory does not already exist
      # ("Error: Failed creating cable directory: Permission denied"). The
      # actual channels are passed separately via `--cable-dir`, which takes
      # precedence, so this directory stays empty on purpose.
      constructFiles = {
        macchiatoTheme = {
          relPath = "themes/catppuccin-macchiato.toml";
          builder = ''${pkgs.remarshal}/bin/json2toml "$1" "$2"'';
          content = builtins.toJSON {
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

        cablePlaceholder.relPath = "cable/.keep";
      };

      # `<out>/cable/.keep` -> `<out>/cable` -> `<out>`, i.e. the wrapper's
      # own output root, which is where `themes/` and `cable/` were just
      # placed.
      env.TELEVISION_CONFIG = builtins.dirOf (builtins.dirOf config.constructFiles.cablePlaceholder.path);
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

        programs.fish.interactiveShellInit = lib.mkAfter ''
          # television's fish integration. Sourced by hand -- and from the
          # unwrapped package, since the wrapper output only carries `bin/` --
          # because the upstream snippet unconditionally binds ctrl-t and
          # ctrl-r. mkAfter (order 1500) puts it after fzf's and atuin's init
          # so the final keymap is explicit rather than dependent on module
          # evaluation order.
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
        '';
      };
    };

  # The worktrunk channel lives in the `dev` bucket because it shells out to
  # `wt`, which is only installed there (development/worktrunk.nix). It mirrors
  # the tmux `prefix C-w` popup, minus the gum/jq pipeline.
  flake.modules.homeManager.dev = {
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
