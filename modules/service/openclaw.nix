{ inputs, ... }:
{
  # Opt-in OpenClaw gateway. The official Home Manager module installs the
  # package, renders ~/.openclaw/openclaw.json, and runs the gateway as the
  # user's openclaw-gateway.service on Linux.
  flake.modules.nixos.openclaw = {
    nixpkgs.overlays = [ inputs.nix-openclaw.overlays.default ];
  };

  flake.modules.homeManager.openclaw = {
    imports = [ inputs.nix-openclaw.homeManagerModules.openclaw ];

    programs.openclaw = {
      enable = true;
      systemd.enable = true;
      config.gateway.mode = "local";
    };

    # nix-openclaw defines the unit but does not install it into a target.
    # Keep the gateway enabled across user-session restarts and WSL boots.
    systemd.user.services.openclaw-gateway.Install.WantedBy = [ "default.target" ];
  };
}
