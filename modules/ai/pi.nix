{ config, inputs, ... }:
let
  # Flake-parts top-level config (extension registry + buildPiExtension live
  # here). Aliased so the wrapper/home-manager submodules below can reach it
  # without their own `config` arg shadowing it.
  outer = config;

  agentsMd = builtins.readFile ./AGENTS.md;

  # Extension sets per variant, by registry name (see modules/ai/extensions/).
  # Mirrors the old baseline + extensions-base (+ extensions-wsl) bundles.
  desktopExtensions = [
    "pi-catppuccin" # Catppuccin theme pack for pi's TUI
    "rpiv-todo" # live todo overlay across reload / compaction
    "notify" # native/Gotify/Telegram/ntfy notifications
    "rpiv-btw" # /btw slash command for side questions
    "rpiv-ask-user-question" # structured questionnaire for the model
    "edb-agent-steer" # steer / queue / discard / edit mid-turn messages
    "pi-interview" # interview-mode extension
    "pi-subagents" # async subagent delegation and coordination
    "pi-hermes-memory" # persistent memory, session search, and secret scanning
    "pi-copilot-discovery" # dynamic GitHub Copilot model discovery
    "pi-nested-agent-md" # inject nested AGENTS.md instructions on file reads
  ];
  wslExtensions = desktopExtensions ++ [
    "pi-wsl-images" # Alt+V image paste from the Windows clipboard
    "agent-browser-edge-bridge" # route agent_browser through Windows Edge (CDP)
    "pi-agent-browser-native" # native browser automation via agent-browser
    "pi-web-access" # web search, URL/repo/PDF/video access
  ];

  # Shared pi wrapper body. `extNames` picks which registry specs to build
  # (lazily, with the wrap-time pkgs) into repeated `--extension` flags. Both
  # variants share this *module* — no wrap-of-a-wrap — so each is a single
  # flat wrapper, like worktrunk/tmux/yazi.
  mkPi =
    extNames:
    {
      pkgs,
      lib,
      wlib,
      config,
      ...
    }:
    let
      # Pi labels CLI-loaded extensions by the *last path segment*, not the
      # package.json `name`. A raw store path shows as
      # `<hash>-pi-ext-pi-interview-0.8.7`; routing each through a linkFarm
      # makes the path `<farm>/pi-interview`, so pi displays the clean name.
      extFarm = pkgs.linkFarm "pi-extensions" (
        lib.mapAttrsToList (name: drv: {
          inherit name;
          path = drv;
        }) (lib.genAttrs extNames (n: outer.flake.lib.buildPiExtension pkgs outer.pi.extensions.${n}))
      );
    in
    {
      imports = [ wlib.modules.default ];

      options.extensions = lib.mkOption {
        type = lib.types.listOf wlib.types.stringable;
        default = [ ];
        description = ''
          Pi extensions to load. Each becomes a `--extension <path>` flag.
          Pi reads each directory's `package.json` `pi` manifest (or falls
          back to convention dirs like `extensions/`, `skills/`, …).
        '';
      };

      options.appendSystemPromptFiles = lib.mkOption {
        type = lib.types.listOf wlib.types.stringable;
        default = [ ];
        description = ''
          Files appended to pi's system prompt via `--append-system-prompt`
          on every invocation (pi reads file contents when the value is an
          existing path).
        '';
      };

      options.configDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "$HOME/.config/pi";
        description = ''
          Override pi's config directory (where `agent/`, sessions, auth,
          packages, etc. live). When non-null, the wrapper sets
          `PI_CODING_AGENT_DIR` for the executable. The value is expanded at
          runtime, so shell variables such as `$HOME` or `$XDG_CONFIG_HOME`
          are ok. Pair this with `binName` to produce separately named pi
          executables (e.g. `pi-msft` -> `$HOME/.config/pi-msft`). An
          explicitly set `PI_CODING_AGENT_DIR` in the environment wins.
        '';
      };

      config = {
        package = pkgs.llm-agents.pi;

        # Self-contained: pi's built-in `bash` tool and several extensions
        # shell out to these. Appended to PATH, so a global install still
        # wins but the wrapper never depends on one being present.
        runtimePkgs = with pkgs; [
          ripgrep # fast recursive search (rg) for the bash tool
          fd # fast file finder for the bash tool
          jq # JSON wrangling for ad-hoc bash tool work
          gh # GitHub CLI for repo lookups / PR work
          lazygit # quick git TUI (extensions may shell out to it)
          bat # nicer file viewer for `bash` tool output
          tree # quick directory inspection
          delta # diff viewer (useful from the bash tool)
          agent-browser # headless browser automation CLI for agents
        ];

        # Build the selected registry specs with the wrap-time pkgs. Routed
        # through `extFarm` so each `--extension` path ends in the clean
        # registry name (see extFarm note above) rather than a store hash.
        extensions = map (n: "${extFarm}/${n}") extNames;

        # Ship the wrapper-local instructions inside the derivation, then
        # append them via CLI. Avoids taking over ~/.pi/agent just to provide
        # global context for this wrapper.
        constructFiles.wrapperAgents = {
          relPath = "share/pi/AGENTS.md";
          content = agentsMd;
        };
        appendSystemPromptFiles = lib.mkBefore [ config.constructFiles.wrapperAgents.path ];

        # `ifs = null` repeats the flag per item rather than joining. Empty
        # lists emit no flags.
        flags."--append-system-prompt" = {
          ifs = null;
          data = map toString config.appendSystemPromptFiles;
        };
        flags."--extension" = {
          ifs = null;
          data = map toString config.extensions;
        };

        # Optional override of the pi config directory for this executable.
        envDefault.PI_CODING_AGENT_DIR = lib.mkIf (config.configDir != null) {
          data = config.configDir;
          esc-fn = x: x;
        };

        # When the wrapper is renamed (e.g. to `pi-msft`), drop the original
        # unwrapped `bin/pi` symlink so the final package only contains the
        # requested executable.
        filesToExclude = lib.mkIf (config.binName != baseNameOf config.exePath) [
          config.exePath
        ];
      };
    };
in
{
  # Two first-class wrappers (auto-exposed as `.#pi-desktop` / `.#pi-wsl`,
  # built by `nix flake check`).
  flake.wrappers.pi-desktop = mkPi desktopExtensions;
  flake.wrappers.pi-wsl = mkPi wslExtensions;

  # Gate option declared in `base` (always imported on every host) so the
  # desktop-core / wsl buckets can install pi only when the ai bucket has
  # also turned it on — i.e. strict "ai AND desktop" / "ai AND wsl".
  flake.modules.homeManager.base =
    { lib, ... }:
    {
      options.pi.enable = lib.mkEnableOption "the pi coding agent (installed by the desktop-core / wsl buckets when the ai bucket is also enabled)";
    };

  # The ai bucket turns pi on.
  flake.modules.homeManager.ai.pi.enable = true;

  # ai AND desktop  -> pi-desktop  (desktop-core is pulled in transitively by
  # the i3 / niri→desktop-wayland buckets).
  flake.modules.homeManager.desktop-core =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.pi.enable {
      home.packages = [
        (outer.flake.wrappers.pi-desktop.wrap { inherit pkgs; })
        (outer.flake.wrappers.pi-desktop.wrap {
          inherit pkgs;
          binName = "pi-msft";
          configDir = "${config.home.homeDirectory}/.config/pi-msft";
        })
      ];
    };

  # ai AND wsl  -> pi-wsl
  flake.modules.homeManager.wsl =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.pi.enable {
      home.packages = [ (outer.flake.wrappers.pi-wsl.wrap { inherit pkgs; }) ];
    };
}
