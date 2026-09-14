{
  # Opt-in: TrueNAS CIFS shares. Hosts that need them import `mounts`.
  flake.modules.nixos.mounts = {
    sops.secrets.truenas = {
      sopsFile = ../../secrets/general.yaml;
      path = "/etc/nixos/smb-truenas";
    };

    fileSystems =
      let
        automount = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
        share = name: {
          device = "//10.0.10.2/${name}";
          fsType = "cifs";
          options = [
            automount
            "credentials=/etc/nixos/smb-truenas"
            "uid=1000"
            "gid=100"
          ];
        };
      in
      {
        "/mnt/media" = share "media";
        "/mnt/photos" = share "photos";
        "/mnt/downloads" = share "downloads";
      };
  };
}
