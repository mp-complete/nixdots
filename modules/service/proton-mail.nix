{ config, ... }:
{
  # ProtonMail Bridge.
  #
  # The stock home-manager unit is `WantedBy/After=graphical-session.target` +
  # `Restart=always`, so it is torn down and restarted on every logout -> login.
  # Proton refresh tokens are single-use (rotating): a token rotated during one
  # session doesn't survive the restart churn, so the next start presents a stale
  # token, the API rejects it (`400 ... auth/v4/refresh: Invalid refresh token,
  # Code=10013`), and the account is forced to "signed out".
  #
  # Fix: run ONE long-lived instance decoupled from the graphical session.
  #   - linger keeps `systemd --user` (and the bridge) alive across logout, so the
  #     unit isn't stopped/started each session;
  #   - binding to default.target (instead of graphical-session.target) starts it
  #     once and keeps it up.
  # The vault key lives in `pass` and the signing key is now passphrase-free, so
  # the bridge can unlock at boot without an interactive pinentry.

  # NixOS: keep the user manager (and the lingering bridge) running across logout.
  flake.modules.nixos.protonmail = {
    users.users.${config.username}.linger = true;
  };

  # home-manager: enable the bridge and detach its unit from graphical-session.
  flake.modules.homeManager.protonmail =
    { lib, ... }:
    {
      services.protonmail-bridge.enable = true;

      systemd.user.services.protonmail-bridge = {
        Unit.After = lib.mkForce [ ];
        Install.WantedBy = lib.mkForce [ "default.target" ];
      };
    };
}
