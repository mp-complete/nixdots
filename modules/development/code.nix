{
  flake.modules.nixos.dev = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.vscode ];
  };
}
