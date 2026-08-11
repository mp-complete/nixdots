{
  repo.aspects.nodejs =
    { pkgs, ... }:
    {
      packages = [ pkgs.nodejs ];
    };
}
