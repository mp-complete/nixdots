{
  # Shared shell options (home-manager scope), read by bash/fish/nushell.
  flake.modules.homeManager.base =
    { lib, ... }:
    {
      options.shell = {
        aliases = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {
            fzfp = "fzf --preview 'bat --color=always {}' --preview-window '~3'";
          };
        };
        initExtra = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Extra init for POSIX shells (bash syntax).";
        };
        fishInitExtra = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = ''
            Extra init for fish (fish syntax). fish gets this instead of
            `initExtra`, whose POSIX/bash syntax is invalid in fish.
          '';
        };
        envExtra = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
        };
      };
    };
}
