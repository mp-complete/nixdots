{ inputs, ... }:
{
  # nvim (a callPackage, not a wrapper) plus the raw nixpkgs pi package.
  # The wrapped tools (tmux, yazi, worktrunk, pi-desktop, pi-wsl, …) are
  # exposed automatically as `packages.<system>.<name>` by each feature's
  # `flake.wrappers` entry — e.g. `nix run .#tmux`, `nix build .#pi-wsl`.
  perSystem =
    { system, ... }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          (final: _prev: {
            nvim = final.callPackage ../../pkgs/neovim {
              inherit (inputs) fennel-ls-nvim-docs;
            };
          })
        ];
      };
      app = drv: bin: {
        type = "app";
        program = "${drv}/bin/${bin}";
        meta.description = "miles's fennel/lua neovim configuration";
      };
    in
    {
      packages = {
        inherit (pkgs) nvim;
      };

      apps = {
        nvim = app pkgs.nvim "nvim";
      };
    };
}
