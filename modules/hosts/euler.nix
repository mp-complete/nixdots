{ mkHost, ... }:
let
  # Human-friendly monitor aliases. niri has no output-aliasing of its own, so
  # we do it here: reference displays by these Nix-level names everywhere, and
  # let each expand to the monitor's stable make/model/serial string (from
  # `niri msg outputs`). make/model/serial is preferred over the connector name
  # (DP-1/DP-2) because it survives replugging into a different port.
  monitors = {
    main = "ViewSonic Corporation VX3276-QHD V9W194342456"; # was DP-2
    side = "ASUSTek COMPUTER INC VG27A NALMQS110328"; # was DP-1 (portrait)
  };
in
{
  flake.nixosConfigurations.euler = mkHost {
    buckets = [
      "base"
      "hardware"
      "nvidia"
      "niri"
      "gaming"
      "printing3d"
      "media-production"
      "protonmail"
      "qmk"
      "dev"
      "ai"
      "skills"
      "syncthing"
      "virt"
      "wine"
      "mounts"
      "wireguard"
      "samba"
      "forgejo-runner"
    ];
    modules = [
      ./euler/_hardware.nix
      ./euler/_display-edid.nix
      {
        networking.hostName = "euler";
        networking.firewall.allowedTCPPorts = [ 8080 ];

        # Never sleep (workstation/server).
        systemd.targets.sleep.enable = false;
        systemd.targets.suspend.enable = false;
        systemd.targets.hibernate.enable = false;
        systemd.targets.hybrid-sleep.enable = false;

        system.stateVersion = "23.11";

        # euler device layer: dual-monitor outputs. Lives at the NixOS level
        # because the niri session package (which bakes this in via NIRI_CONFIG)
        # is installed into the system profile.
        # (nvidia env vars come from the `nvidia` bucket's sessionVariables.)
        desktop = {
          outputs = {
            # Main — ViewSonic VX3276-QHD
            ${monitors.main} = {
              mode = "2560x1440@59.950";
              position = _: {
                props = {
                  x = 0;
                  y = 0;
                };
              };
              focus-at-startup = { };
            };
            # Side — ASUS VG27A (portrait)
            ${monitors.side} = {
              mode = "2560x1440@143.970";
              position = _: {
                props = {
                  x = 2560;
                  y = -8;
                };
              };
              transform = "90";
            };
          };
          # Bind all named workspaces to the main monitor.
          workspaces = {
            "1-main".open-on-output = monitors.main;
            "2-browser".open-on-output = monitors.main;
            "3-dev".open-on-output = monitors.main;
            "4-chat".open-on-output = monitors.main;
            "5-media".open-on-output = monitors.main;
          };
        };

        home-manager.users.miles = {
          my.ai.aider.enable = true;
          my.ai.opencode.enable = true;
          my.ai.copilot-cli.enable = true;
          my.ai.copilot-cli.notifications.enable = true;
        };
      }
    ];
  };
}
