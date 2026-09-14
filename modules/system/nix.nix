{
  flake.modules.nixos.base = {
    nixpkgs.config.allowUnfree = true;

    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      substituters = [
        "https://nix-community.cachix.org"
        "https://niri.cachix.org"
        "https://noctalia.cachix.org"
        "https://zen-browser.cachix.org"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
        "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
        "zen-browser.cachix.org-1:JqFj1EF0dz5hhk0n+NuYPBvmHGMsEPPiku56OK0GDzo="
      ];
      max-jobs = "auto";
      auto-optimise-store = true;
    };

    # `mpc` registry alias → milespossing/flakes
    nix.registry.mpc.to = {
      type = "github";
      owner = "milespossing";
      repo = "flakes";
    };
  };
}
