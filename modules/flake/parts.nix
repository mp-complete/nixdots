{ inputs, lib, ... }:
{
  imports = [
    inputs.flake-parts.flakeModules.modules
    inputs.nix-wrapper-modules.flakeModules.wrappers
  ];

  systems = [ "x86_64-linux" ];

  perSystem =
    { system, pkgs, ... }:
    {
      # flake-parts' default `pkgs` is `inputs.nixpkgs.legacyPackages.<system>`,
      # which carries no nixpkgs config — so unfree-licensed derivations fail to
      # evaluate on the flake side even though NixOS hosts allow them. Only the
      # Elastic-2.0 licensed context-mode pi extension needs this; keep the
      # allowance windowed to that package rather than blanket-allowing unfree.
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg: lib.getName pkg == "context-mode";
      };

      formatter = pkgs.nixfmt-tree;
    };
}
