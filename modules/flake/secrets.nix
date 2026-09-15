{ inputs, ... }:
{
  # sops-nix wiring. Per-feature secret declarations live next to their feature
  # (network/mounts.nix, network/wireguard.nix, ai/secrets.nix). NixOS secrets
  # use each machine's root-owned SSH host key via sops-nix's default
  # `sops.age.sshKeyPaths` discovery.
  flake.modules.nixos.base.imports = [ inputs.sops-nix.nixosModules.sops ];
}
