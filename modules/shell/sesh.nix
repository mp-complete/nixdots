{
  # sesh -- the smart tmux session manager (https://github.com/joshmedeski/sesh).
  #
  # sesh was already wired into the workflow before it was ever installed:
  #   - modules/shell/tmux.nix          : `bind b` gum popup + `bind C-w` worktree switcher
  #   - modules/development/worktrunk.nix: the `wt-sesh` / `wtc` aliases
  # This file finally puts the binary on PATH in the core shell (base bucket)
  # and ships a declarative sesh.toml. sesh drives tmux sessions off zoxide --
  # both tmux (the wrapper) and zoxide (shell/tools.nix) are already enabled in
  # this bucket, so no extra dependencies are needed.
  flake.modules.homeManager.base =
    { osConfig, pkgs, ... }:
    {
      home.packages = [ pkgs.sesh ];

      # ~/.config/sesh/sesh.toml -- sesh reads this path by default, so no
      # `--config` flag is required. The picker preview uses eza (installed in
      # shell/tools.nix). Per-project `startup_command`s are intentionally left
      # out so new sessions don't force-launch anything; add `[[session]]` /
      # `[[wildcard]]` entries here as needed.
      xdg.configFile."sesh/sesh.toml".source = (pkgs.formats.toml { }).generate "sesh.toml" {
        default_session = {
          preview_command = "eza --all --git --icons --color=always {}";
        };

        # Named sessions always available in the picker (`sesh list -c`).
        # The flake checkout lives at a different path per host
        # (`~/.config/nixdots` on hilbert/general2, `~/.config/nixos` on the
        # `nixos` host), so take it from `programs.nh.flake` instead of
        # hardcoding one: sesh expands `~` but not `$NH_FLAKE`, and a session
        # whose `path` does not exist silently starts in `$HOME` instead.
        session = [
          {
            name = "nixos config";
            path = osConfig.programs.nh.flake;
            preview_command = "eza --all --git --icons --color=always {}";
          }
        ];
      };
    };
}
