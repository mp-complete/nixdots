{ inputs, lib, ... }:
let
  overlay = inputs.llm-agents.overlays.shared-nixpkgs;
in
{
  # Use the consumer's nixpkgs for llm-agents packages, including flake-side
  # wrapper outputs such as pi-desktop and pi-wsl.
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [ overlay ];

        # Only the Elastic-2.0 licensed context-mode pi extension needs this;
        # keep the flake-side allowance narrower than allowUnfree = true.
        config.allowUnfreePredicate = pkg: lib.getName pkg == "context-mode";
      };
    };

  # Hosts use this package set through NixOS and Home Manager's useGlobalPkgs.
  flake.modules.nixos.base.nixpkgs.overlays = [ overlay ];
}
