{ config, ... }:
{
  # Deliberately unconfigured. worktrunk's user config
  # (`~/.config/worktrunk/config.toml`) is a layer it *writes to* itself:
  # `wt config create`/`update` migrations, the first-run
  # `skip-shell-integration-prompt` / `skip-commit-generation-prompt` flags,
  # and — via `approvals_path() = config_path().with_file_name(...)` —
  # `approvals.toml`, where `wt` records approved hook commands.
  #
  # Pinning it into the store with `WORKTRUNK_CONFIG_PATH` made all of those
  # writes fail silently, so hook approvals could never persist. worktrunk has
  # a lower, read-only `system` layer meant for this (`/etc/xdg/worktrunk/`,
  # or `WORKTRUNK_SYSTEM_CONFIG_PATH`), but with only a handful of settings
  # worth declaring, it isn't worth the split-brain. The user config is now
  # hand-managed; see <https://worktrunk.dev/config/>.
  flake.wrappers.worktrunk =
    { pkgs, wlib, ... }:
    {
      imports = [ wlib.modules.default ];
      # The base package (worktrunk flake input) is supplied by the registry.
      config.package = pkgs.worktrunk;
    };

  # worktrunk: Git worktree management CLI (https://worktrunk.dev).
  #
  # The binary is installed at the system layer, wrapped via wrappers/worktrunk
  # (base package is the worktrunk flake input, injected into the overlay in
  # modules/flake/wrappers.nix).
  flake.modules.nixos.dev =
    { pkgs, ... }:
    {
      environment.systemPackages = [ (config.flake.wrappers.worktrunk.wrap { inherit pkgs; }) ];
    };

  # Its interactive-shell integration (the bash-init hook + the wt-sesh/wta/wtc
  # abbreviations) must run in the user's shell, so it stays in the shell layer
  # alongside fzf/zoxide/atuin/direnv. References the wrapped pkgs.worktrunk.
  flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      programs.bash.initExtra = ''
        eval "$(${config.flake.wrappers.worktrunk.wrap { inherit pkgs; }}/bin/wt config shell init bash)"
      '';
      programs.fish.shellInit = ''
        ${config.flake.wrappers.worktrunk.wrap { inherit pkgs; }}/bin/wt config shell init fish | source
      '';

      # fish abbreviations rather than `home.shellAliases`. The latter already
      # became abbrs in fish (`preferAbbrs`, shell/fish.nix) and these were
      # never useful in bash -- bash is the login shell but immediately execs
      # into fish (shell/fish.nix), so the bash aliases were dead weight.
      # Declaring them here also makes the fish-only semantics explicit: the
      # expansion lands in the buffer, so the `$(git branch | fzf ...)` in
      # wt-sesh is visible and editable before it runs.
      #
      # Counts from atuin: `wt switch <branch>` 82, `wt list` 26 -- the two
      # bare `wt` subcommands that survive alongside the fuzzy paths
      # (`tvw` / tmux `prefix C-w`), which handle picking rather than typing.
      programs.fish.shellAbbrs = {
        wt-sesh = "wt switch --no-cd -x 'sesh connect {{ worktree_path }}' $(git branch | fzf | cut -c 3-)";
        # Keep the branch before `--`; `sh -c` resolves the configured agent
        # while using worktrunk's forward-compatible single-program form.
        wta = {
          expansion = "wt switch --create --base=@ --execute sh % -- -c 'exec \"$AGENT\"'";
          setCursor = "%";
        };
        wtc = "wt switch --no-cd -x 'sesh connect {{ worktree_path }}' -c";
        wtl = "wt list";
        wts = "wt switch";
      };
    };
}
