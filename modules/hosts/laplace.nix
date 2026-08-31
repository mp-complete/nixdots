{ mkHost, inputs, ... }:
{
  flake.nixosConfigurations.laplace = mkHost {
    buckets = [
      "base"
      "hardware"
      "networkmanager"
      "sway"
      "dev"
      "ai"
      "skills"
      "syncthing"
    ];
    modules = [
      inputs.nixos-hardware.nixosModules.framework-13-7040-amd
      ./laplace/_hardware.nix
      {
        networking.hostName = "laplace";
        system.stateVersion = "25.11";

        home-manager.users.miles = {
          my.ai.copilot-cli.enable = true;
        };
      }
    ];
  };
}
