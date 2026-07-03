{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      fonts.enableDefaultPackages = true;
      fonts.fontDir.enable = true;
      fonts.packages = with pkgs; [
        cozette
        font-awesome
        hack-font
        material-design-icons
        noto-fonts
        noto-fonts-color-emoji
        noto-fonts-cjk-sans
        nerd-fonts.departure-mono
        nerd-fonts.jetbrains-mono
        nerd-fonts.fira-mono
        nerd-fonts.fira-code
        nerd-fonts.droid-sans-mono
        nerd-fonts.noto
      ];
    };
}
