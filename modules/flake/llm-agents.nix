{ inputs, lib, ... }:
let
  overlays = [
    inputs.llm-agents.overlays.shared-nixpkgs

    # Bun 1.3.13 standalone executables produced by `bun build --compile`
    # currently segfault on NixOS/WSL. Pi supports a Node-based build for this
    # case; keep it under the same pkgs.llm-agents.pi attribute.
    (_final: prev: {
      llm-agents = prev.llm-agents // {
        pi = prev.llm-agents.pi.override { useBun = false; };
      };
    })
  ];
in
{
  # Use the consumer's nixpkgs for llm-agents packages, including flake-side
  # wrapper outputs such as pi-desktop and pi-wsl.
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        inherit overlays;

        # Only the Elastic-2.0 licensed context-mode pi extension needs this;
        # keep the flake-side allowance narrower than allowUnfree = true.
        config.allowUnfreePredicate = pkg: lib.getName pkg == "context-mode";
      };
    };

  # Hosts use this package set through NixOS and Home Manager's useGlobalPkgs.
  flake.modules.nixos.base.nixpkgs.overlays = overlays;
}
