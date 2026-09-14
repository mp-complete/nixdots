{ inputs, ... }:
let
  overlays = [
    # Use Numtide's Node runtime variant. The default Bun-compiled pi 0.85.1
    # binary segfaults before `--version` or `--help` can produce output.
    (final: _prev: {
      pi-coding-agent =
        inputs.llm-agents.packages.${final.stdenv.hostPlatform.system}.pi.override
          { useBun = false; };
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
