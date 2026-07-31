{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      programs.fish = {
        enable = true;
        generateCompletions = true;
        plugins = [
          {
            name = "fzf-fish";
            src = pkgs.fishPlugins.fzf-fish.src;
          }
        ];
      };
    };
}
