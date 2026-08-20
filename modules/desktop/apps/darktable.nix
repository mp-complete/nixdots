{
  ...
}:
{
  flake.modules.nixos.photography = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.darktable ];
  };
}
