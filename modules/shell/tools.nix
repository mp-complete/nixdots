{
  flake.modules.homeManager.base =
    { pkgs, ... }:
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
