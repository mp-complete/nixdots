{ inputs, ... }:
{
  # Noctalia 5.x desktop shell (bar/launcher/notifications) for niri.
  #
  # Installed via the upstream home-manager module (`programs.noctalia`) from the
  # `noctalia` flake input — NOT the nix-wrapper-modules wrapper, which only
  # understands noctalia 4.x's JSON config. 5.x is a C++ rewrite that reads a
  # TOML `config.toml` from ~/.config/noctalia and writes GUI/runtime overrides
  # to a separate state-dir `settings.toml`, so a declarative (read-only) config
  # works without the old `outOfStoreConfig` copy hack.
  #
  # Starting fresh: no `settings` yet — noctalia boots with its built-in defaults
  # and is configured via its GUI. To declare config later, set
  # `programs.noctalia.settings` (a TOML attrset). See https://docs.noctalia.dev/v5.
  flake.modules.homeManager.noctalia = {
    imports = [ inputs.noctalia.homeModules.default ];

    programs.noctalia = {
      enable = true;
      # niri spawns noctalia via spawn-at-startup, so no systemd user service.
      systemd.enable = false;
    };
  };
}
