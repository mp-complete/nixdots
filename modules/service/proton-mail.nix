{ ... }:
{
  # ProtonMail Bridge.
  #
  # Started after login so the GNOME keyring (unlocked by PAM at login via
  # security.pam.services.greetd.enableGnomeKeyring) is available when the
  # bridge starts. This lets the bridge retrieve its vault key and actually
  # encrypt the vault — under linger the bridge started before any keyring was
  # unlocked and fell back to running with an unencrypted vault.
  #
  # Token-rotation safety: Proton issues single-use rotating refresh tokens.
  # A 30s TimeoutStopSec gives the bridge time to flush the rotated token back
  # to the vault before systemd escalates to SIGKILL. If you upgrade the bridge
  # or otherwise need to restart it, do so manually:
  #   systemctl --user restart protonmail-bridge

  flake.modules.nixos.protonmail = { };

  flake.modules.homeManager.protonmail =
    { lib, ... }:
    {
      services.protonmail-bridge.enable = true;

      systemd.user.services.protonmail-bridge = {
        Unit.After = lib.mkForce [
          "graphical-session.target"
          "network-online.target"
        ];
        Unit.Wants = [ "network-online.target" ];
        Install.WantedBy = lib.mkForce [ "graphical-session.target" ];
        Service.TimeoutStopSec = "30";
      };
    };
}
