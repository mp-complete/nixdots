{
  # desktop-core: DE-agnostic graphical base (both nixos + home sides).
  flake.modules.nixos.desktop-core =
    { pkgs, ... }:
    {
      programs.dconf.enable = true;

      services.gvfs.enable = true;
      services.udisks2.enable = true;
      services.gnome.gnome-keyring.enable = true;

      xdg.portal = {
        enable = true;
        config.common.default = "*";
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      };

      environment.systemPackages = with pkgs; [
        libsecret
        seahorse
        polkit_gnome
      ];
    };

  # Home side of desktop-core (theme + tray utilities + clipboard tools).
  flake.modules.homeManager.desktop-core =
    { pkgs, ... }:
    {
      services.udiskie = {
        enable = true;
        tray = "never";
      };

      home.packages = with pkgs; [
        brightnessctl
        pamixer
        playerctl
        networkmanagerapplet
        pavucontrol
        blueman # bluetooth GUI; waybar's bluetooth widget opens blueman-manager
        libnotify
        xclip
        flameshot
      ];

      home.pointerCursor = {
        name = "catppuccin-macchiato-mauve-cursors";
        package = pkgs.catppuccin-cursors.macchiatoMauve;
        size = 24;
        gtk.enable = true;
      };

      gtk = {
        enable = true;
        gtk4.theme = {
          name = "catppuccin-macchiato-mauve-standard+default";
          package = pkgs.catppuccin-gtk.override {
            accents = [ "mauve" ];
            variant = "macchiato";
          };
        };
        iconTheme = {
          name = "Papirus-Dark";
          package = pkgs.catppuccin-papirus-folders.override {
            accent = "mauve";
            flavor = "macchiato";
          };
        };
      };
    };
}
