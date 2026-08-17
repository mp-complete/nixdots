{
  flake.modules.devShell.typescript =
    { pkgs, ... }:
    {
      packages = [ pkgs.typescript ];
    };
}
