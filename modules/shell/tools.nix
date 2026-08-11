{ config, lib, ... }:
let
  directoryCases = lib.concatStringsSep "\n" (
    lib.flatten (
      lib.mapAttrsToList (
        shellName: shell:
        map (
          directory: "${lib.escapeShellArg directory}) shell=${lib.escapeShellArg shellName} ;;"
        ) shell.directories
      ) config.repo.shells
    )
  );
in
{
  flake.modules.homeManager.base =
    {
      lib,
      osConfig,
      pkgs,
      ...
    }:
    {
      home.shellAliases.fzfp = "fzf --preview 'bat --color=always {}' --preview-window '~3'";

      programs.fzf = {
        enable = true;
        defaultCommand = "fd --type f";
        enableBashIntegration = true;
        enableFishIntegration = true;
        # Yield Ctrl-R to atuin, which owns shell history search here.
        historyWidget.command = "";
      };
      programs.zoxide = {
        enable = true;
        enableBashIntegration = true;
        enableFishIntegration = true;
        enableNushellIntegration = true;
      };
      programs.eza = {
        enable = true;
        icons = "auto";
        git = true;
      };
      programs.direnv = {
        enable = true;
        enableBashIntegration = true;
        enableNushellIntegration = true;
        nix-direnv.enable = true;
        stdlib = ''
          # Load a repository shell from this machine's nixdots flake. With no
          # argument, resolve the shell from repo.shells.*.directories and then
          # fall back to the current directory basename.
          # Usage from .envrc: use nixdots [shell]
          use_nixdots() {
            if [[ $# -gt 1 ]]; then
              log_error "usage: use nixdots [shell]"
              return 1
            fi

            local shell="''${1:-}"
            if [[ -z "$shell" ]]; then
              case "''${PWD##*/}" in
                ${directoryCases}
                *) shell="''${PWD##*/}" ;;
              esac
            fi

            local flake_path=${lib.escapeShellArg osConfig.programs.nh.flake}
            local development_path="$flake_path/modules/development"

            # nix-direnv normally watches only flake.nix and flake.lock for an
            # external flake. Include aspect definitions and their directories
            # so edits and newly added aspects invalidate the cached shell.
            while IFS= read -r path; do
              watch_file "$path"
            done < <(${pkgs.findutils}/bin/find "$development_path" \
              \( -type d -o \( -type f -name '*.nix' \) \) -print)

            use flake "path:$flake_path#$shell"
          }
        '';
      };
      programs.atuin = {
        enable = true;
        enableBashIntegration = true;
        enableFishIntegration = true;
        enableNushellIntegration = true;
        flags = [ "--disable-up-arrow" ];
        settings = {
          sync_frequency = "5m";
          filter_mode = "directory";
          filter_mode_shell_up_arrow = "session";
        };
      };
      home.packages = with pkgs; [
        gum
        ripgrep
        fd
        bat
        jq # used bare in the tmux worktrunk popup + general CLI JSON
        sd # used by the normalize-json navi cheat
        # modern-unix CLI set (was modules/core/programs.nix pre-dendritic)
        htop
        btop
        gojq
        yq
        glow
        dust
        duf
        procs
        xh
        hyperfine
        tokei
        sqlite
        parallel
      ];
    };
}
