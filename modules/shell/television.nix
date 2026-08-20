{
  # television (`tv`) -- https://alexpasmantier.github.io/television/
  #
  # A "Telescope.nvim for the terminal": one picker UI, many declarative data
  # sources. Each source is a *channel* -- a TOML file under
  # `~/.config/television/cable/` describing `[source]` -> `[preview]` ->
  # `[actions]`. Compare fzf (shell/tools.nix), which is a primitive you glue
  # workflows around by hand.
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
  # Channels come from two places, both fully declarative:
  #   * upstream's community set, linked straight out of `television.src`
  #     (see `upstreamChannels`) instead of running `tv update-channels`,
  #     which downloads them over the network at runtime;
  #   * repo-specific ones written in Nix via `programs.television.channels`.
  flake.modules.homeManager.base =
    {
      config,
      lib,
      osConfig,
      pkgs,
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
        "tmux-sessions"
        "tmux-windows"
      ];

      # This flake's checkout, same source of truth direnv's `use nixdots`
      # uses in shell/tools.nix.
      flakePath = osConfig.programs.nh.flake;

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
      programs.television = {
        enable = true;

        # All four shell integrations are off: the packaged snippets hard-code
        # ctrl-t/ctrl-r and land at the default `interactiveShellInit` order,
        # where they race fzf's and atuin's own init. fish is wired up by hand
        # in `mkAfter` at the bottom of this file so the final keymap is
        # deterministic; bash only exists to re-exec into fish (shell/fish.nix)
        # and nushell is not an interactive shell here.
        enableFishIntegration = false;
        enableBashIntegration = false;
        enableZshIntegration = false;
        enableNushellIntegration = false;

        # `tv` is wrapped with these on PATH. Channel `[source]`/`[preview]`
        # commands run through $SHELL and so mostly resolve from the user
        # profile anyway, but this keeps tv working when invoked from a
        # stripped environment (tmux popups, systemd units).
        extraPackages = with pkgs; [
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

        # Custom channels. These are written to cable/*.toml alongside the
        # vendored upstream ones; names must not collide with
        # `upstreamChannels` above.
        channels.nixdots = {
          metadata = {
            name = "nixdots";
            description = "Files in this flake (${flakePath})";
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
                run = "cd ${flakePath} && fd -t f -e nix";
              }
              {
                name = "All";
                run = "cd ${flakePath} && fd -t f";
              }
              {
                name = "Modules";
                run = "cd ${flakePath}/modules && fd -t f -e nix";
              }
            ];
          };
          preview = {
            command = "bat -n --color=always '${flakePath}/{}'";
            env.BAT_THEME = "ansi";
          };
          keybindings.enter = "actions:edit";
          actions.edit = {
            description = "Open the selected file in $EDITOR";
            command = "\${EDITOR:-vim} '${flakePath}/{}'";
            shell = "bash";
            mode = "execute";
          };
        };
      };

      # Vendored upstream channels. `xdg.configFile` is used directly rather
      # than `programs.television.channels` because these are already TOML on
      # disk -- round-tripping them through Nix would mean re-implementing (and
      # then maintaining) upstream's templating.
      xdg.configFile = lib.listToAttrs (
        map (
          channel:
          lib.nameValuePair "television/cable/${channel}.toml" { source = "${cable}/${channel}.toml"; }
        ) upstreamChannels
      );

      programs.fish.interactiveShellInit = lib.mkAfter ''
        # television's fish integration, sourced by hand instead of via
        # `programs.television.enableFishIntegration`. The upstream snippet
        # unconditionally binds ctrl-t and ctrl-r, and home-manager emits it at
        # the default `interactiveShellInit` order -- the same order fzf and
        # atuin use -- so "who wins" would depend on module evaluation order.
        # mkAfter (order 1500) puts it last and makes the keymap explicit.
        source ${config.programs.television.package}/share/television/completion.fish

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

  # The worktrunk channel lives in the `dev` bucket because it shells out to
  # `wt`, which is only installed there (development/worktrunk.nix). It mirrors
  # the tmux `prefix C-w` popup, minus the gum/jq pipeline.
  flake.modules.homeManager.dev = {
    programs.television.channels.worktrunk = {
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
