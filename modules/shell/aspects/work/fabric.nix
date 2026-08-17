{
  flake.modules.devShell.fabric =
    { pkgs, ... }:
    {
      packages = with pkgs; [
        copilot-cli
      ];
    };
}
