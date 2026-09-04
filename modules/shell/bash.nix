{
  flake.modules.homeManager.base = {
    programs.home-manager.enable = true;

    home.sessionVariables = {
      AGENT = "pi";
      EDITOR = "nvim";
      VISUAL = "nvim";
    };

    programs.bash.enable = true;
    programs.nushell.enable = true;
  };
}
