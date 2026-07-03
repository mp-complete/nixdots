{ config, ... }:
{
  # i3 (X11) — euler's WM. Pulls the X11 layer (→ desktop-core) and wires the
  # matching home-manager config.
  flake.modules.nixos.i3 =
    { pkgs, ... }:
    {
      imports = [ config.flake.modules.nixos.desktop-x11 ];

      services.xserver.windowManager.i3 = {
        enable = true;
        extraPackages = with pkgs; [
          i3status
          dmenu
        ];
      };
      services.displayManager.defaultSession = "none+i3";
    };

  flake.modules.homeManager.i3 =
    { pkgs, ... }:
    let
      mod = "Mod4";
      terminal = config.terminal.command;
      menu = "rofi -show drun -show-icons";
    in
    {
      imports = [ config.flake.modules.homeManager.desktop-core ];

      home.packages = [
        (config.flake.wrappers.rofi.wrap { inherit pkgs; })
        (config.flake.wrappers.dunst.wrap { inherit pkgs; })
        pkgs.i3lock
      ];

      xsession.windowManager.i3 = {
        enable = true;
        config = {
          modifier = mod;
          terminal = terminal;
          menu = menu;
          fonts = {
            names = [ "DepartureMono Nerd Font" ];
            size = 11.0;
          };
          gaps = {
            inner = 5;
            outer = 5;
          };
          window = {
            border = 2;
            titlebar = false;
          };
          focus.followMouse = true;

          keybindings = {
            "${mod}+Return" = "exec ${terminal}";
            "${mod}+q" = "kill";
            "${mod}+d" = "exec ${menu}";
            "${mod}+e" = "exec ${terminal} -e yazi";
            "${mod}+v" = "floating toggle";
            "${mod}+f" = "fullscreen toggle";
            "${mod}+s" = "layout stacking";
            "${mod}+w" = "layout tabbed";
            "${mod}+t" = "layout toggle split";
            "${mod}+Shift+e" = "exec i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'";
            "${mod}+Shift+c" = "reload";
            "${mod}+Shift+r" = "restart";

            "${mod}+h" = "focus left";
            "${mod}+j" = "focus down";
            "${mod}+k" = "focus up";
            "${mod}+l" = "focus right";
            "${mod}+Left" = "focus left";
            "${mod}+Down" = "focus down";
            "${mod}+Up" = "focus up";
            "${mod}+Right" = "focus right";

            "${mod}+Shift+h" = "move left";
            "${mod}+Shift+j" = "move down";
            "${mod}+Shift+k" = "move up";
            "${mod}+Shift+l" = "move right";

            "${mod}+1" = "workspace number 1";
            "${mod}+2" = "workspace number 2";
            "${mod}+3" = "workspace number 3";
            "${mod}+4" = "workspace number 4";
            "${mod}+5" = "workspace number 5";
            "${mod}+6" = "workspace number 6";
            "${mod}+7" = "workspace number 7";
            "${mod}+8" = "workspace number 8";
            "${mod}+9" = "workspace number 9";
            "${mod}+0" = "workspace number 10";

            "${mod}+Shift+1" = "move container to workspace number 1";
            "${mod}+Shift+2" = "move container to workspace number 2";
            "${mod}+Shift+3" = "move container to workspace number 3";
            "${mod}+Shift+4" = "move container to workspace number 4";
            "${mod}+Shift+5" = "move container to workspace number 5";
            "${mod}+Shift+6" = "move container to workspace number 6";
            "${mod}+Shift+7" = "move container to workspace number 7";
            "${mod}+Shift+8" = "move container to workspace number 8";
            "${mod}+Shift+9" = "move container to workspace number 9";
            "${mod}+Shift+0" = "move container to workspace number 10";

            "${mod}+r" = "mode resize";
            "Print" = "exec flameshot gui";

            "XF86AudioMute" = "exec pamixer -t";
            "XF86AudioRaiseVolume" = "exec pamixer -i 5";
            "XF86AudioLowerVolume" = "exec pamixer -d 5";
            "XF86AudioPlay" = "exec playerctl play-pause";
            "XF86AudioNext" = "exec playerctl next";
            "XF86AudioPrev" = "exec playerctl previous";
          };

          modes.resize = {
            "h" = "resize shrink width 20px";
            "l" = "resize grow width 20px";
            "k" = "resize shrink height 20px";
            "j" = "resize grow height 20px";
            "Escape" = "mode default";
            "Return" = "mode default";
          };

          startup = [
            {
              command = "nm-applet";
              notification = false;
            }
            {
              command = "dunst";
              notification = false;
            }
          ];
        };
      };
    };
}
