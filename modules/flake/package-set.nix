{ inputs, ... }:
let
  overlays = [
    # Alias Numtide's unchanged package, rather than rebuilding it against
    # our nixpkgs, so all Pi wrappers retain upstream cache compatibility.
    (final: _prev: {
      pi-coding-agent = inputs.llm-agents.packages.${final.stdenv.hostPlatform.system}.pi;
    })
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
