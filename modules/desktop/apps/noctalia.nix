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
  # The declarative base config lives in `./noctalia-config.toml`, dumped from a
  # live-configured instance's runtime state (`~/.local/state/noctalia/settings.toml`).
  # noctalia reads this as `~/.config/noctalia/config.toml` (a read-only base) and
  # still writes GUI/runtime overrides to its own state `settings.toml`. To refresh
  # this file after tweaking things in the GUI, re-copy the state settings.toml over
  # it. See https://docs.noctalia.dev/v5.
  flake.modules.homeManager.noctalia = {
    imports = [ inputs.noctalia.homeModules.default ];

    programs.noctalia = {
      enable = true;
      # niri spawns noctalia via spawn-at-startup, so no systemd user service.
      systemd.enable = false;
      # Validated at build time via `noctalia config validate`.
      settings = ./noctalia-config.toml;
    };
  };
}
