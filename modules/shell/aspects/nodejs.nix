{
  flake.modules.devShell.nodejs =
    { pkgs, ... }:
    {
      packages = [ pkgs.nodejs ];
    };
}
