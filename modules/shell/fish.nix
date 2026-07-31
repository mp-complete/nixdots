{
  flake.modules.homeManager.base =
    { config, pkgs, ... }:
    {
      programs.fish = {
        enable = true;
        generateCompletions = true;
        shellAliases = config.shell.aliases;
        shellInit = config.shell.fishInitExtra;
        plugins = [
          {
            name = "fzf-fish";
            src = pkgs.fishPlugins.fzf-fish.src;
          }
        ];
      };
    };
}
