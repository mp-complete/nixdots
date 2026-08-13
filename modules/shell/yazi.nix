{ config, ... }:
{
  flake.wrappers.yazi =
    {
      pkgs,
      wlib,
      config,
      ...
    }:
    let
      yazi-flavors = pkgs.fetchFromGitHub {
        owner = "yazi-rs";
        repo = "flavors";
        rev = "3001521a0885fc281d0456df5a28394dec850dc6";
        hash = "sha256-lzts4koNg0l0tMkPku8lpb2X4juBs72NREwzca3UCLs=";
      };
      path-from-root = pkgs.fetchFromGitHub {
        owner = "aresler";
        repo = "path-from-root.yazi";
        rev = "3daa62fa01681cff8bb62eb0bd72e59245486846";
        hash = "sha256-2jW+NoEd5ZrcoPnS7Pv7xfWH/lypUJdjF7z3CYZM7Lg=";
      };
    in
    {
      imports = [ wlib.wrapperModules.yazi ];
      package = pkgs.yazi;
      # Self-contained: keymaps shell out to `zellij`, and the git plugin/fetcher
      # invokes `git`.
      runtimePkgs = with pkgs; [
        zellij
        git
      ];

      plugins = with pkgs.yaziPlugins; {
        inherit
          smart-enter
          full-border
          git
          chmod
          smart-filter
          jump-to-char
          ;
        path-from-root = "${path-from-root}";
        paste-image = ./_yazi/paste-image.yazi;
      };

      flavors = {
        macchiato = "${yazi-flavors}/catppuccin-macchiato.yazi";
      };

      settings = {
        yazi.plugin.prepend_fetchers = [
          {
            url = "*";
            run = "git";
            group = "git";
          }
          {
            url = "*/";
            run = "git";
            group = "git";
          }
        ];

        keymap.mgr.prepend_keymap = [
          {
            on = "<C-h>";
            run = "shell 'zellij action move-focus-or-tab left' --confirm";
            desc = "Move zellij focus left";
          }
          {
            on = "<C-j>";
            run = "shell 'zellij action move-focus down' --confirm";
            desc = "Move zellij focus down";
          }
          {
            on = "<C-k>";
            run = "shell 'zellij action move-focus up' --confirm";
            desc = "Move zellij focus up";
          }
          {
            on = "<C-l>";
            run = "shell 'zellij action move-focus-or-tab right' --confirm";
            desc = "Move zellij focus right";
          }
          {
            on = [
              "c"
              "r"
            ];
            run = "plugin path-from-root";
            desc = "Copy path relative to git root";
          }
          {
            on = [
              "c"
              "i"
            ];
            run = "plugin paste-image";
            desc = "Paste Windows clipboard image";
          }
        ];
      };

      constructFiles.luaInit = {
        content = # lua
          ''
            require("full-border"):setup()
            require("git"):setup()
          '';
        relPath = "${config.binName}-config/init.lua";
      };
    };
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      programs.yazi = {
        enable = true;
        package = config.flake.wrappers.yazi.wrap { inherit pkgs; };
        enableBashIntegration = true;
        enableFishIntegration = true;
        enableNushellIntegration = true;
        shellWrapperName = "y";
      };
    };
}
