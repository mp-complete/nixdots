{ config, lib, ... }:
{
  # `nix flake check` builds every host's system.build.toplevel, which
  # transitively builds the wrappers each host actually installs (kitty, tmux,
  # pi-coding-agent-*, …). The registry's `packages.<system>.*` outputs
  # are evaluated alongside. This replaces the manual
  # `nix eval .#nixosConfigurations.<h>.config.system.build.toplevel.drvPath`
  # loop and gives CI (.github/) a single validation entrypoint.
  perSystem =
    { system, ... }:
    {
      checks = lib.mapAttrs (_: cfg: cfg.config.system.build.toplevel) (
        lib.filterAttrs (
          _: cfg: cfg.config.nixpkgs.hostPlatform.system == system
        ) config.flake.nixosConfigurations
      );
    };
}
