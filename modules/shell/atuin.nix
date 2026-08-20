{ inputs, ... }:
{
  # atuin -- https://docs.atuin.sh/
  #
  # Shell history as a SQLite store rather than a flat file: every command is a
  # row carrying cwd, session, exit code, duration and host. That metadata is
  # what the filter modes below trade on, and it is the reason ctrl-r belongs to
  # atuin instead of tv's `fish-history` channel, which can only fuzzy-match
  # lines out of ~/.local/share/fish/fish_history (see shell/television.nix).
  flake.modules.homeManager.base = {
    programs.atuin = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      enableNushellIntegration = true;

      # Route history writes through a long-lived daemon instead of having every
      # shell hook open the SQLite store directly. That kills the per-command
      # write contention (and the "database is locked" stalls) you get with many
      # concurrent shells, and moves sync off the interactive path.
      #
      # home-manager wires this as a socket-activated systemd user unit and sets
      # `daemon.enabled` / `daemon.systemd_socket` for us, so atuin's own
      # `daemon.autostart` stays off (its default) -- systemd owns the lifecycle.
      daemon.enable = true;

      # Up-arrow stays fish's own prefix search; ctrl-r is atuin's.
      #
      # `--disable-ai` is not redundant with `ai.enabled = false` below. atuin
      # 18.18 binds `?` to its AI chat at init time, and home-manager pre-renders
      # `atuin init fish` in a build sandbox with a throwaway HOME -- that
      # generation never sees our config.toml, so only the flag keeps `?` free in
      # fish. The setting covers the paths that read config at runtime.
      flags = [
        "--disable-up-arrow"
        "--disable-ai"
      ];

      settings = {
        sync_frequency = "5m";
        # ctrl-r defaults to "commands I ran in this directory"; the shell's
        # up-arrow (when atuin is bound to it) scopes to the current session.
        filter_mode = "directory";
        filter_mode_shell_up_arrow = "session";

        # No LLM in the shell history tool. This also stops `?` on an empty
        # prompt from opening the AI UI.
        ai.enabled = false;
      };
    };
  };

  # Opt-in: hosts that sync history import `atuin-sync`.
  #
  # The sync store is end-to-end encrypted with a key that the server never
  # sees, so the key file is the only copy -- lose it and the synced history is
  # undecryptable and no new host can join. Ship it via sops instead of leaving
  # it as an unmanaged, unbacked-up file in the data dir.
  #
  # `key_path` points at the decrypted secret (tmpfs, mode 0400) rather than
  # copying it into ~/.local/share/atuin/key, so the plaintext key never lands
  # on disk. That is safe against atuin rewriting it: `load_key` only reads an
  # existing file, and `atuin login` writes only when the key is absent or
  # differs from the one supplied -- with a read-only match it is a no-op, and a
  # mismatched login fails loudly instead of silently re-encrypting the store.
  #
  # Requires ~/.config/sops/age/keys.txt on the host, the same bootstrap the
  # `wsl` bucket's gpg-bootstrap.nix already depends on.
  flake.modules.homeManager.atuin-sync =
    {
      config,
      lib,
      ...
    }:
    {
      imports = [ inputs.sops-nix.homeManagerModules.sops ];

      sops = {
        age.keyFile = lib.mkDefault "${config.home.homeDirectory}/.config/sops/age/keys.txt";
        secrets.atuin_key.sopsFile = ./atuin-key.enc.yaml;
      };

      programs.atuin.settings.key_path = config.sops.secrets.atuin_key.path;
    };
}
