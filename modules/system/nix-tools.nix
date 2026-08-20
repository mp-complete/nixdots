{ inputs, lib, ... }:
{
  flake.modules.nixos.base = {
    imports = [ inputs.nix-index-database.nixosModules.default ];
    programs.nix-index-database.comma.enable = true;
    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 4d --keep 3";
      flake = lib.mkDefault "/home/miles/src/nixdots";
    };
  };

  # Abbreviations for the three commands this flake is actually driven by.
  # From `atuin history list | uniq -c`: `nh os switch` 170, `nix flake check`
  # 19, `nix flake update` 13. Abbreviations rather than aliases so the real
  # command lands in the buffer (and in atuin) and stays editable -- `nfu` then
  # `space` leaves room to append an input name, which is how `nix flake update
  # alexandria` gets typed.
  flake.modules.homeManager.base = {
    programs.fish.shellAbbrs = {
      nos = "nh os switch";
      nfc = "nix flake check";
      nfu = "nix flake update";
    };
  };
}
