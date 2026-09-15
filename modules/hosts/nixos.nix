{ mkHost, ... }:
{
  # WSL work host.
  flake.nixosConfigurations.nixos = mkHost {
    buckets = [
      "base"
      "dev"
      "ai"
      "openclaw-node"
      "skills"
      "syncthing"
      "work"
      "wsl"
    ];
    modules = [
      {
        networking.hostName = "nixos";
        programs.nh.flake = "/home/miles/.config/nixos";
        system.stateVersion = "26.05";
      }
    ];
  };
}
