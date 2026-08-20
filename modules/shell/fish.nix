{
  flake.modules.homeManager.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Catppuccin Macchiato, taken verbatim from the [dark] section of
      # catppuccin/fish's themes/catppuccin-macchiato.theme. Matches kitty
      # (desktop/apps/kitty.nix), yazi (shell/yazi.nix), rofi
      # (desktop/apps/rofi.nix) and tv (shell/television.nix), which were
      # already themed while fish alone kept its stock colours.
      #
      # Applied with `set -g` from config.fish rather than `fish_config theme
      # choose`, which writes *universal* variables into
      # ~/.config/fish/fish_variables -- state outside the store that would
      # then silently shadow whatever this file says.
      fishColors = {
        fish_color_normal = "cad3f5";
        fish_color_command = "8aadf4";
        fish_color_param = "f0c6c6";
        fish_color_keyword = "c6a0f6";
        fish_color_quote = "a6da95";
        fish_color_redirection = "f5bde6";
        fish_color_end = "f5a97f";
        fish_color_comment = "8087a2";
        fish_color_error = "ed8796";
        fish_color_gray = "6e738d";
        fish_color_selection = "--background=363a4f";
        fish_color_search_match = "--background=363a4f";
        fish_color_option = "a6da95";
        fish_color_operator = "f5bde6";
        fish_color_escape = "ee99a0";
        fish_color_autosuggestion = "6e738d";
        fish_color_cancel = "ed8796";
        fish_color_cwd = "eed49f";
        fish_color_user = "8bd5ca";
        fish_color_host = "8aadf4";
        fish_color_host_remote = "a6da95";
        fish_color_status = "ed8796";
        fish_pager_color_progress = "6e738d";
        fish_pager_color_prefix = "f5bde6";
        fish_pager_color_completion = "cad3f5";
        fish_pager_color_description = "6e738d";
      };
    in
    {
      programs.fish = {
        enable = true;
        generateCompletions = true;
        # Render `home.shellAliases` as fish *abbreviations* rather than
        # aliases: the expansion is written into the command line before it
        # runs, so it stays editable and atuin records what actually ran
        # instead of an opaque alias name.
        preferAbbrs = true;
        plugins = [
          {
            name = "fzf-fish";
            src = pkgs.fishPlugins.fzf-fish.src;
          }
        ];

        interactiveShellInit = ''
          # fish otherwise prints a two-line "Welcome to fish" banner in every
          # new shell -- which here means every tmux pane, every `display-popup`
          # and every sesh session. `set -g`, not `set -U`: universal variables
          # persist in fish_variables and outlive this config.
          set -g fish_greeting

          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: value: "set -g ${name} ${value}") fishColors
          )}

          # fzf-fish plugin knobs, pointed at tools this config already sets up
          # rather than the plugin's defaults:
          #   * delta is git's pager and interactive.diffFilter
          #     (development/git.nix), so ctrl-alt-s previews match `git diff`
          #   * eza with the same flags as sesh's preview_command
          #     (shell/sesh.nix) and `programs.eza` (shell/tools.nix)
          #   * `--hidden` because dotfiles are the point of this repo;
          #     `programs.fzf.defaultCommand` (`fd --type f`) skips them
          set -g fzf_diff_highlighter delta --paging=never
          set -g fzf_preview_dir_cmd eza --all --icons --color=always
          set -g fzf_fd_opts --hidden --exclude=.git
        '';
      };

      # fish is the default *interactive* shell, but bash remains the login
      # shell (users.defaultUserShell = bash) for compatibility with scripts,
      # display managers, and remote `ssh host cmd`. An interactive bash then
      # re-execs into fish. Guards (mkBefore so we bail before the other
      # bash-only init in this bucket runs):
      #   * parent's command isn't fish -> no loop when fish shells out to bash
      #   * BASH_EXECUTION_STRING empty -> `bash -c …` / scripts stay bash
      programs.bash.initExtra = lib.mkBefore ''
        if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]; then
          exec ${config.programs.fish.package}/bin/fish
        fi
      '';
    };
}
