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
          init.defaultBranch = "main";
          pull.rebase = false;

          # `histogram` is patience+ and handles the "moved block of similar
          # lines" case (repeated `}`/`end`/list entries) that Myers shreds.
          # Kept in sync with neovim's `diffopt` (pkgs/neovim/fnl/config/diff.fnl)
          # so `git diff` and `git difftool` agree on where the hunks are.
          diff.algorithm = "histogram";
          diff.colorMoved = "default";
          diff.tool = "nvimdiff";
          # `git difftool` otherwise asks "Launch 'nvimdiff' [Y/n]?" per file,
          # which is pure noise when the tool is already the configured default.
          # `git mergetool` keeps its prompt: there it's the last chance to skip
          # a file before its conflict markers get rewritten.
          difftool.prompt = false;

          merge.tool = "nvimdiff";
          # zdiff3 shows the merge base between `|||||||` and `=======`, so a
          # conflict says what *changed* on each side rather than just showing
          # two final states. It also hoists lines common to both sides out of
          # the conflict region, which shrinks most conflicts noticeably.
          merge.conflictStyle = "zdiff3";
          # Record how each conflict was resolved and replay it automatically
          # the next time the same conflict shows up -- i.e. every rebase of a
          # long-lived branch, where the same hunk conflicts once per commit.
          rerere = {
            enabled = true;
            autoUpdate = true;
          };

          http.postBuffer = 524288000;
          mergetool = {
            keepBackup = false;
            # Feed the mergetool a MERGED buffer with the already-auto-resolved
            # hunks collapsed, so the three panes only disagree where the
            # conflict actually is.
            hideResolved = true;
            # git's vimdiff backend builds this layout: LOCAL / BASE / REMOTE
            # across the top, the MERGED buffer (the one you edit and save)
            # full-width below. Spelled out because it is the knob to turn if
            # the 4-way split is too cramped -- e.g. "LOCAL,MERGED,REMOTE" for
            # a 3-pane view that drops BASE, or "@LOCAL,REMOTE+BASE,MERGED" to
            # put BASE in a tab. See `git help mergetool`, MERGETOOL_VIMDIFF.
            nvimdiff.layout = "LOCAL,BASE,REMOTE / MERGED";
          };
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
          "/.lsp"
          "/.clj-kondo"
          ".nrepl-port"
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

        gs = "git status";
        ga = "git add";
        # difftool/mergetool are long to type and the tool is worth having
        # visible in the buffer -- these expand in place, so appending
        # `-t bcompare` (modules/wsl/beyond-compare.nix) or a pathspec is just
        # more typing on the same line.
        gdt = "git difftool";
        gmt = "git mergetool";
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
