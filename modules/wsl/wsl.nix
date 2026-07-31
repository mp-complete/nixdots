{
  inputs,
  config,
  ...
}:
{
  flake.modules.nixos.wsl =
    { pkgs, lib, ... }:
    {
      imports = [ inputs.nixos-wsl.nixosModules.wsl ];
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

      # WSL manages /etc/resolv.conf itself; systemd-resolved (enabled globally
      # in network/manager.nix) would conflict, so turn it off on WSL.
      services.resolved.enable = lib.mkForce false;

      wsl = {
        enable = true;
        defaultUser = config.username;
        wslConf.automount.options = "metadata,umask=22,fmask=11";
      };

      # Run unpatched dynamically-linked binaries (corporate .NET tools).
      programs.nix-ld.enable = true;
      programs.nix-ld.libraries = with pkgs; [
        stdenv.cc.cc
        openssl
        icu
        zlib
        curl
      ];

      # Secret Service backed by pass/GPG (replaces gnome-keyring on WSL).
      services.dbus.packages = [ pkgs.pass-secret-service ];
      systemd.user.services.pass-secret-service = {
        description = "Pass-backed Secret Service";
        serviceConfig = {
          ExecStart = "${pkgs.pass-secret-service}/bin/pass_secret_service";
          BusName = "org.freedesktop.secrets";
        };
      };
      environment.systemPackages = [
        pkgs.libsecret
        pkgs.zathura
      ];
    };

  flake.modules.homeManager.wsl =
    { pkgs, ... }:
    {
      programs.gpg.enable = true;
      programs.password-store.enable = true;
      # Adopt HM's new default (PASSWORD_STORE_DIR unset => ~/.password-store),
      # matching gpg-bootstrap.nix which initializes $HOME/.password-store.
      programs.password-store.settings = { };
      fonts.fontconfig.enable = true;
      home.packages = with pkgs; [
        wsl-open
        xdg-utils
      ];
      shell.initExtra = "export WSL=1";
      shell.fishInitExtra = "set -gx WSL 1";
    };
}
