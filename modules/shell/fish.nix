{
  flake.modules.homeManager.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
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

      # fish is the default *interactive* shell, but bash remains the login
      # shell (users.defaultUserShell = bash) for compatibility with scripts,
      # display managers, and remote `ssh host cmd`. An interactive bash then
      # re-execs into fish. Guards (mkBefore so we bail before the other
      # bash-only init in this bucket runs):
      #   * parent's command isn't fish -> no loop when fish shells out to bash
      #   * BASH_EXECUTION_STRING empty -> `bash -c …` / scripts stay bash
      programs.bash.initExtra = lib.mkBefore ''
        if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]; then
          exec ${config.programs.fish.package}/bin/fish
        fi
      '';
    };
}
