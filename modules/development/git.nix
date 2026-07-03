{ config, lib, ... }:
{
  options.git = {
    userName = lib.mkOption {
      type = lib.types.str;
      default = "Miles Possing";
    };
    userEmail = lib.mkOption {
      type = lib.types.str;
      default = "mp-complete@pm.me";
    };
  };

  config.flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      programs.git = {
        enable = true;
        settings = {
          user.name = config.git.userName;
          user.email = config.git.userEmail;
          aliases = {
            s = "status";
            c = "checkout";
            d = "diff";
          };
          init.defaultBranch = "main";
          pull.rebase = false;
          diff.tool = "nvimdiff";
          diff.colorMoved = "default";
          merge.tool = "nvimdiff";
          http.postBuffer = 524288000;
          mergetool.keepBackup = false;
          push.autoSetupRemote = true;
          core = {
            editor = "nvim";
            pager = "delta";
          };
          interactive.diffFilter = "delta --color-only";
          delta = {
            navigate = true;
            dark = true;
            line-numbers = true;
            syntax-theme = "Catppuccin Macchiato";
          };
        };
        ignores = [
          "*~"
          "*.swp"
          ".\\#*"
          "\\#*\\#"
          "venv/"
          ".direnv"
          ".envrc"
        ];
      };
      programs.gh.enable = true;
      programs.lazygit.enable = true;
      home.packages = [ pkgs.delta ];
    };
}
