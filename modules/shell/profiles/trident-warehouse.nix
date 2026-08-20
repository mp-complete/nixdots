{ config, mkDevShell, ... }:
{
  flake.modules.devShell.trident-warehouse = {
    imports = with config.flake.modules.devShell; [
      nodejs
      typescript
      yarn
      playwright
    ];
  };

  perSystem =
    { pkgs, ... }:
    {
      devShells.trident-warehouse =
        mkDevShell pkgs "trident-warehouse"
          config.flake.modules.devShell.trident-warehouse;
    };

  # worktrunk settings for this repo live in the hand-managed user config at
  # `~/.config/worktrunk/config.toml`, not here — see modules/development/worktrunk.nix.
}
