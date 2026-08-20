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

      # Up-arrow stays fish's own prefix search; ctrl-r is atuin's.
      flags = [ "--disable-up-arrow" ];

      settings = {
        sync_frequency = "5m";
        # ctrl-r defaults to "commands I ran in this directory"; the shell's
        # up-arrow (when atuin is bound to it) scopes to the current session.
        filter_mode = "directory";
        filter_mode_shell_up_arrow = "session";
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
