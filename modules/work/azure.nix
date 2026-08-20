{ ... }:
{
  flake.modules.nixos.work =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        (pkgs.azure-cli.withExtensions [
          pkgs.azure-cli.extensions.azure-devops
          pkgs.azure-cli.extensions.kusto
        ])
      ];
    };
}
