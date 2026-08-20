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

  # Its interactive-shell integration (the bash-init hook + the wt-sesh/wtc
  # aliases) must run in the user's shell, so it stays in the shell layer
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
      home.shellAliases = {
        wt-sesh = "wt switch --no-cd -x 'sesh connect {{ worktree_path }}' $(git branch | fzf | cut -c 3-)";
        wtc = "wt switch --no-cd -x 'sesh connect {{ worktree_path }}' -c";
      };
    };
}
