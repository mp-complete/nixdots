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
    forgejoUrls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "https://git.opencurry.xyz" ];
      example = [ "https://git.example.com" ];
      description = ''
        Self-hosted Forgejo base URLs to authenticate to via git-credential-oauth
        (browser OAuth). Forgejo advertises WWW-Authenticate realm="Forgejo",
        which GCM does not recognize, so it needs the dedicated helper. Forgejo
        ships a pre-registered OAuth2 app for git-credential-oauth, so no client
        registration is required, even self-hosted.
      '';
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
          # github.com uses gh; Azure DevOps etc. use GCM (see work/gcm.nix).
          # Self-hosted Forgejo needs git-credential-oauth for the browser flow.
          credential = lib.mkMerge (
            [
              {
                # The leading empty helper resets any inherited default helper
                # (e.g. GCM from work/gcm.nix) so only gh is consulted here.
                "https://github.com".helper = [
                  ""
                  "!${pkgs.gh}/bin/gh auth git-credential"
                ];
              }
            ]
            ++ map (url: {
              ${url}.helper = [
                "" # reset any inherited helper (e.g. GCM as default)
                "cache --timeout 21600" # 6h in-memory cache of token + refresh token
                "${pkgs.git-credential-oauth}/bin/git-credential-oauth"
              ];
            }) config.git.forgejoUrls
          );
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

      # home-manager's lazygit module ships an `lg` fish function that honours
      # LAZYGIT_NEW_DIR_FILE, i.e. it follows lazygit's `cd` on exit. History
      # says bare `lazygit` still gets typed 44 times over `lg`, throwing that
      # away; rewrite it at command position (so `command lazygit` still works).
      programs.fish.shellAbbrs = {
        lazygit = {
          position = "command";
          expansion = "lg";
        };

        # The three git invocations that are typed verbatim, with no arguments
        # to vary. From atuin: `git pull` 57, `git fetch --all` 26,
        # `git fetch origin` 6 (plus a handful with a branch appended, which
        # still works -- the abbr expands on the space before the branch name).
        # Deliberately no `gst`/`gpu`: `git s` already exists as a git alias
        # (above) and `git push` is only 12 uses, both below the bar the other
        # abbrs in this config cleared.
        gp = "git pull";
        gfa = "git fetch --all";
        gfo = "git fetch origin";
      };
      home.packages = [
        pkgs.delta
      ]
      ++ lib.optional (config.git.forgejoUrls != [ ]) pkgs.git-credential-oauth;
    };
}
