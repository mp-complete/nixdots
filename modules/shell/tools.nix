{ lib, ... }:
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
          # Load an explicitly named development shell from this machine's
          # nixdots flake. Usage from .envrc: use nixdots <shell>
          use_nixdots() {
            if [[ $# -ne 1 ]]; then
              log_error "usage: use nixdots <shell>"
              return 1
            fi

            local shell="$1"
            local flake_path=${lib.escapeShellArg osConfig.programs.nh.flake}
            local shell_path="$flake_path/modules/shell"

            # nix-direnv normally watches only flake.nix and flake.lock for an
            # external flake. Include development-shell modules and their
            # directories so edits and new aspects invalidate the cached shell.
            while IFS= read -r path; do
              watch_file "$path"
            done < <(${pkgs.findutils}/bin/find "$shell_path" \
              \( -type d -o \( -type f -name '*.nix' \) \) -print)

            use flake "path:$flake_path#$shell"
          }
        '';
      };
      # NB: `programs.atuin` is configured in shell/atuin.nix, not here. Two
      # definitions of `flags` in the same bucket concatenate rather than
      # override, and `atuin init` rejects a repeated `--disable-up-arrow`,
      # which made home-manager emit an empty fish integration file.
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
