{ inputs, ... }:
let
  overlays = [
    # Provide `pkgs.pi-coding-agent` from lukasl-dev/pi.nix.
    inputs.pi-nix.overlays.default
  ];
in
{
  # Use the consumer's nixpkgs for flake-side wrapper outputs such as
  # pi-desktop and pi-wsl.
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        inherit overlays;
      };
    };

  # Hosts use this package set through NixOS and Home Manager's useGlobalPkgs.
  flake.modules.nixos.base.nixpkgs.overlays = overlays;
}
