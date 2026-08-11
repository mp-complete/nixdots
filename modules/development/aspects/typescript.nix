{
  repo.aspects.typescript =
    { pkgs, ... }:
    {
      packages = [ pkgs.typescript ];
    };
}
