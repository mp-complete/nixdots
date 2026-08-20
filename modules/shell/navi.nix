{
  flake.modules.homeManager.base =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      # Cheatsheet repositories, pinned rather than fetched by `navi repo add`
      # -- that command writes to navi's *default* cheats dir
      # (~/.local/share/navi/cheats), which is deliberately absent from
      # `cheats.paths` below, so anything imported that way would be invisible
      # here anyway.
      #
      # denisidoro/navi-tldr-pages used to be in this list and was removed: it
      # contributes 23,155 snippets against ~600 from denisidoro/cheats and one
      # of our own, so `--best-match` (which is what ctrl-g runs against
      # whatever is already on the prompt) practically always resolved into
      # tldr, and every navi invocation paid ~300ms parsing it instead of
      # ~55ms. `navi --tldr <cmd>` covers the same ground on demand; add
      # `pkgs.tealdeer` plus `settings.client.tealdeer = true` if that should
      # read a local cache rather than hit the network.
      repos = [
        {
          owner = "denisidoro";
          repo = "cheats";
          rev = "1339965e9615ce00174cc308a41279d9c59aa75f";
          sha256 = "0j2xqlq4a104jk1gmr9xr0803r9wfjv6apy6s1pgha0661mh1yy0";
        }
      ];

      repoPaths = map (
        r:
        "${pkgs.fetchFromGitHub {
          inherit (r)
            owner
            repo
            rev
            sha256
            ;
        }}"
      ) repos;

      # Catppuccin Macchiato, same palette as shell/television.nix and
      # shell/fish.nix. Spelled out in hex (unlike `style` below) because fzf
      # takes real colours rather than crossterm's 16 names.
      macchiato = {
        base = "#24273a";
        text = "#cad3f5";
        surface0 = "#363a4f";
        surface1 = "#494d64";
        rosewater = "#f4dbd6";
        lavender = "#b7bdf8";
        mauve = "#c6a0f6";
        red = "#ed8796";
      };

      fzfColors = lib.concatStringsSep " " [
        "--color=bg:${macchiato.base},bg+:${macchiato.surface0},fg:${macchiato.text},fg+:${macchiato.text}"
        "--color=hl:${macchiato.red},hl+:${macchiato.red},header:${macchiato.red}"
        "--color=info:${macchiato.mauve},prompt:${macchiato.mauve},pointer:${macchiato.rosewater}"
        "--color=spinner:${macchiato.rosewater},marker:${macchiato.lavender}"
        "--color=selected-bg:${macchiato.surface1},border:${macchiato.surface0},label:${macchiato.text}"
      ];

      # Locally authored cheats are staged into ~/.cheats/<name> rather than
      # read straight out of the store so that config.yaml holds a stable path
      # and does not churn on every cheat edit.
      localPaths = lib.mapAttrsToList (
        name: _: "${config.home.homeDirectory}/.cheats/${name}"
      ) config.navi.cheatDirs;
    in
    {
      options.navi.cheatDirs = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
        example = lib.literalExpression "{ wsl = ./_navi/wsl; }";
        description = ''
          Directories of locally authored `.cheat` files, keyed by the name
          they get under `~/.cheats/`. Each one is staged with `home.file` and
          added to navi's `cheats.paths`.

          An option rather than a plain list so that buckets other than `base`
          can contribute cheats that only make sense on some hosts -- see
          `wsl/navi.nix`, whose cheats shell out to `pwsh.exe`.
        '';
      };

      config = {
        home.file = lib.mapAttrs' (
          name: source:
          lib.nameValuePair ".cheats/${name}" {
            inherit source;
            recursive = true;
          }
        ) config.navi.cheatDirs;

        navi.cheatDirs.common = ./_navi/common;

        programs.navi = {
          enable = true;
          enableBashIntegration = true;
          # The widget is sourced by hand in `interactiveShellInit` below
          # instead; see the comment there.
          enableFishIntegration = false;

          settings = {
            cheats.paths = localPaths ++ repoPaths;

            # navi parses these through crossterm, which accepts *only* the
            # 16 ANSI colour names (plus `reset`) -- hex, `rgb_(r,g,b)` and
            # raw ANSI indices are all rejected at config load, and navi then
            # silently falls back to its defaults. That is fine here: kitty
            # remaps ANSI 0-15 to Catppuccin Macchiato
            # (desktop/apps/kitty.nix), so naming a colour picks up the same
            # palette as tv, yazi and fish.
            #
            # The mapping mirrors fish's own syntax highlighting
            # (shell/fish.nix): the snippet column is a command, so it gets
            # fish_color_command's blue; the tag column is a label, so it gets
            # the pink used for fish_color_redirection and tv's channel-mode
            # badge.
            style = {
              # Tags are short now that tldr's `common`/`linux` sheets are
              # gone -- the widest in denisidoro/cheats is 37 chars but the
              # median is one word -- so the default 26%/20ch reservation was
              # mostly whitespace stolen from the snippet column.
              tag = {
                color = "magenta";
                width_percentage = 16;
                min_width = 12;
              };
              comment = {
                color = "white";
                width_percentage = 40;
                min_width = 40;
              };
              snippet.color = "blue";
            };

            finder = {
              command = "fzf";

              # navi shells out to a bare `fzf`, and nothing here sets
              # FZF_DEFAULT_OPTS or `programs.fzf.defaultOptions`, so its
              # picker was the one stock-themed surface left. Scoped to navi
              # rather than set globally because fzf-fish's widgets
              # (shell/fish.nix) have not been through that decision.
              #
              # navi already passes --preview/--preview-window/--delimiter/
              # --ansi/--exact and a ctrl-j/ctrl-k binding; overrides are
              # appended last, so these win where they overlap.
              overrides = lib.concatStringsSep " " [
                "--height=80%"
                "--border=rounded"
                fzfColors
              ];

              # The variable picker is a short list of candidate values, not a
              # corpus to browse; a full-height window for `git branch` output
              # is mostly empty space.
              overrides_var = lib.concatStringsSep " " [
                "--height=40%"
                "--border=rounded"
                fzfColors
              ];
            };
          };
        };

        # navi's own fish widget is sourced here rather than via
        # `enableFishIntegration`, which puts it in `shellInit` (i.e. every
        # non-interactive `fish -c` too) and, more importantly, ships a
        # version with two bugs that upstream has fixed on master but not in
        # any release -- not 2.24.0, not 2.25.0-beta1:
        #
        #   * `commandline --current-process $candidate` treats newlines as
        #     process boundaries, flattening multi-line snippets onto one line
        #   * fish >= 4 needs an explicit repaint after fzf clobbers the
        #     terminal (fish-shell#5033, fish-shell#5860; navi PR #982)
        #
        # This version additionally pipes through `string collect`, which
        # upstream's fix does not: `set x (navi --print)` splits the output
        # into a list at newlines, so even `--replace -- "$x"` re-joins a
        # multi-line snippet with spaces.
        #
        # Drop this whole block for `enableFishIntegration = true` once a navi
        # release contains navi PR #982.
        programs.fish.interactiveShellInit = ''
          function _navi_smart_replace --description "Replace the current command with a navi snippet"
              set --local query (commandline --current-process | string trim)
              set --local candidate

              # With a partial command on the prompt, take navi's best match
              # outright; fall back to the interactive picker when it has no
              # opinion (and always, on an empty prompt).
              if test -n "$query"
                  set candidate (${config.programs.navi.package}/bin/navi --print --query "$query" --best-match | string collect)
              end
              if test -z "$candidate"
                  set candidate (${config.programs.navi.package}/bin/navi --print --query "$query" | string collect)
              end

              if test -n "$candidate"
                  commandline --replace -- "$candidate"
                  commandline --function end-of-line
              end

              # Unconditional: fzf has drawn over the prompt whether or not
              # anything was selected.
              commandline --function repaint
          end

          for mode in default insert
              bind --mode $mode ctrl-g _navi_smart_replace
          end
        '';
      };
    };
}
