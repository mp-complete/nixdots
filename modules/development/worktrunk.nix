{ config, ... }:
{
  flake.wrappers.worktrunk =
    {
      config,
      lib,
      wlib,
      pkgs,
      ...
    }:
    let
      tomlType = wlib.types.structuredValueWith {
        nullable = false;
        typeName = "TOML";
      };
      hasConfig = config.settings != { };
    in
    {
      imports = [ wlib.modules.default ];

      options.settings = lib.mkOption {
        type = tomlType;
        default = { };
        example = {
          worktree-path = "~/worktrees/{{repo}}/{{branch}}";
        };
        description = ''
          Contents of worktrunk's `config.toml`, delivered via
          `WORKTRUNK_CONFIG_PATH`. See <https://worktrunk.dev/config/>.
        '';
      };

      config = {
        package = pkgs.worktrunk;
        # The base package (worktrunk flake input) is supplied by the registry.
        env.WORKTRUNK_CONFIG_PATH = lib.mkIf hasConfig "${placeholder config.outputName}/${config.binName}-config/config.toml";

        constructFiles.config = lib.mkIf hasConfig {
          relPath = lib.mkOverride 0 "${config.binName}-config/config.toml";
          content = builtins.toJSON config.settings;
          builder = ''${pkgs.remarshal}/bin/json2toml "$1" "$2"'';
        };
      };
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
      shell.initExtra = ''
        eval "$(${config.flake.wrappers.worktrunk.wrap { inherit pkgs; }}/bin/wt config shell init bash)"
      '';
      shell.fishInitExtra = ''
        ${config.flake.wrappers.worktrunk.wrap { inherit pkgs; }}/bin/wt config shell init fish | source
      '';
      shell.aliases = {
        wt-sesh = "wt switch --no-cd -x 'sesh connect {{ worktree_path }}' $(git branch | fzf | cut -c 3-)";
        wtc = "wt switch --no-cd -x 'sesh connect {{ worktree_path }}' -c";
      };
    };
}
