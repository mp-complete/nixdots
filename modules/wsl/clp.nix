{
  flake.modules.nixos.wsl = {
    nixpkgs.overlays = [
      (final: _prev: {
        clp = final.callPackage ../../pkgs/clp { };
      })
    ];
  };

  flake.modules.homeManager.wsl = { pkgs, ... }: {
    home.packages = [ pkgs.clp ];
  };
}
