# let
#   color-picker = pkgs.writeShellScript "niri-color-picker" ''
#     ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp -p)" -t ppm - \
#       | ${pkgs.imagemagick}/bin/magick - -format '%[pixel:p{0,0}]' txt:- \
#       | tail -1 | grep -oP '#[0-9a-fA-F]+' | ${pkgs.wl-clipboard}/bin/wl-copy
#     ${pkgs.libnotify}/bin/notify-send "Color Picker" "$(${pkgs.wl-clipboard}/bin/wl-paste)"
#   '';
#
#   cliphist-cmd = "${pkgs.cliphist}/bin/cliphist list | rofi -dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy";
# in
{ config, lib, inputs, ... }:
let
  flake = config.flake;
  terminal = config.terminal;
in
{
  flake.wrappers.niri =
    {
      config,
      wlib,
      pkgs,
      ...
    }:
    {
      imports = [ wlib.wrapperModules.niri ];

      env = {
        XDG_SESSION_TYPE = "wayland";
        NIXOS_OZONE_WL = "1";
        ELECTRON_OZONE_PLATFORM_HINT = "auto";
        DISPLAY = ":0";
      };

      settings = {
        prefer-no-csd = { };
        screenshot-path = "~/Pictures/Screenshots/Screenshot_%Y-%m-%d_%H-%M-%S.png";
        hotkey-overlay.skip-at-startup = { };
        input = {
          keyboard.xkb.layout = "us";
          focus-follows-mouse = { };
          warp-mouse-to-focus = { };
          workspace-auto-back-and-forth = { };
        };

        layout = {
          gaps = 5;
          struts = {
            left = 0;
            right = 0;
            top = 0;
            bottom = 0;
          };
          # "never" keeps columns packed/stable so a 50/50 (or 33/33/33) set
          # stays side-by-side as you move focus between them, instead of
          # re-centering and breaking up the pair. always-center-single-column
          # still centers a lone column for a tidy solo view.
          center-focused-column = "never";
          always-center-single-column = { };
          preset-column-widths = [
            { proportion = 0.33333; }
            { proportion = 0.5; }
            { proportion = 0.66667; }
            { proportion = 1.0; }
          ];
          # Heights cycled by switch-preset-window-height (Mod+Shift+R) for a
          # window stacked in a column.
          preset-window-heights = [
            { proportion = 0.33333; }
            { proportion = 0.5; }
            { proportion = 0.66667; }
          ];
          default-column-width.proportion = 0.5;
          focus-ring = {
            width = 0.5;
          };
          border = {
            width = 0.5;
            active-color = "#c6a0f6";
            inactive-color = "#5b6078";
            urgent-color = "#ed8796";
          };
          # Tabbed columns (Mod+T) draw one segment per stacked window so you
          # can see/count what's in the stack. Hidden for single-window columns.
          tab-indicator = {
            hide-when-single-tab = { };
            place-within-column = { };
            gap = 4;
            width = 4;
            length = _: { props.total-proportion = 0.5; };
            position = "left";
            gaps-between-tabs = 4;
            corner-radius = 4;
            active-color = "#c6a0f6";
            inactive-color = "#5b6078";
            urgent-color = "#ed8796";
          };
          shadow = {
            on = { };
            softness = 12;
            spread = 5;
            offset = _: {
              params = {
                x = 0;
                y = 5;
              };
            };
            draw-behind-window = false;
            color = "#181926cc";
            inactive-color = "#18192666";
          };
        };

        overview.zoom = 0.5;

        animations = {
          slowdown = 1.0;
          workspace-switch.spring = _: {
            props = {
              damping-ratio = 1.0;
              stiffness = 800;
              epsilon = 0.0001;
            };
          };
          window-open = {
            duration-ms = 200;
            curve = "ease-out-expo";
          };
          window-close = {
            duration-ms = 150;
            curve = "ease-out-quad";
          };
          horizontal-view-movement.spring = _: {
            props = {
              damping-ratio = 1.0;
              stiffness = 800;
              epsilon = 0.0001;
            };
          };
          window-movement.spring = _: {
            props = {
              damping-ratio = 1.0;
              stiffness = 800;
              epsilon = 0.0001;
            };
          };
          window-resize.spring = _: {
            props = {
              damping-ratio = 1.0;
              stiffness = 800;
              epsilon = 0.0001;
            };
          };
          config-notification-open-close.spring = _: {
            props = {
              damping-ratio = 0.6;
              stiffness = 1000;
              epsilon = 0.001;
            };
          };
        };

        spawn-at-startup = [
          [
            "${pkgs.xwayland-satellite}/bin/xwayland-satellite"
            ":0"
          ]
          [
            "nm-applet"
            "--indicator"
          ]
          [
            "${pkgs.wl-clipboard}/bin/wl-paste"
            "--type"
            "text"
            "--watch"
            "${pkgs.cliphist}/bin/cliphist"
            "store"
          ]
          [
            "${pkgs.wl-clipboard}/bin/wl-paste"
            "--type"
            "image"
            "--watch"
            "${pkgs.cliphist}/bin/cliphist"
            "store"
          ]
          [ "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1" ]
          [ (lib.getExe inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default) ]
        ];

        window-rules = [
          {
            matches = [ { } ];
            geometry-corner-radius = 10;
            clip-to-geometry = true;
          }
          {
            matches = [ { app-id = "pavucontrol"; } ];
            open-floating = true;
          }
          {
            matches = [ { app-id = "nm-connection-editor"; } ];
            open-floating = true;
          }
          {
            matches = [
              {
                app-id = "firefox";
                title = "^Picture-in-Picture$";
              }
            ];
            open-floating = true;
          }
          {
            matches = [ { app-id = "zen"; } ];
            open-on-workspace = "browser";
          }
          {
            matches = [ { app-id = "firefox"; } ];
            excludes = [
              {
                app-id = "firefox";
                title = "^Picture-in-Picture$";
              }
            ];
            open-on-workspace = "browser";
          }
          {
            matches = [ { app-id = "^discord$"; } ];
            open-on-workspace = "chat";
          }
          {
            matches = [ { app-id = "^Spotify$"; } ];
            open-on-workspace = "media";
          }
        ];

        # Named workspaces. Keys are numeric-prefixed to fix their order (niri
        # sorts workspaces by key); `name` is the friendly handle referenced by
        # window-rules' open-on-workspace. Host modules pin them to outputs.
        workspaces = {
          "1-main" = { };
          "2-browser" = { };
          "3-dev" = { };
          "4-chat" = { };
          "5-media" = { };
        };

        binds =
          let
            rofi = lib.getExe (flake.wrappers.rofi.wrap { inherit pkgs; });
            basicAction = a: { "${a}" = { }; };
            action = a: v: { "${a}" = v; };
            columnWidth = s: action "set-column-width" s;
            columnHeight = s: action "set-window-height" s;
          in
          {
            "Mod+Return".spawn = terminal.command;
            "Mod+E".spawn = [
              terminal.command
              "-e"
              "yazi"
            ];
            "Mod+D".spawn = [
              rofi
              "-show"
              "drun"
              "-show-icons"
            ];

            # Nav
            "Mod+H" = basicAction "focus-column-left";
            "Mod+L" = basicAction "focus-column-right";
            "Mod+K" = basicAction "focus-window-up";
            "Mod+J" = basicAction "focus-window-down";

            # Window Management
            "Mod+Q" = basicAction "close-window";
            "Mod+Shift+E" = basicAction "quit";
            "Mod+V" = basicAction "toggle-window-floating";
            "Mod+F" = basicAction "maximize-column";
            "Mod+Shift+F" = basicAction "fullscreen-window";
            "Mod+C" = basicAction "center-column";
            # Center the whole visible group (e.g. a pair/triple) as a unit,
            # rather than a single column like Mod+C.
            "Mod+Shift+C" = basicAction "center-visible-columns";
            # Grow the focused column into space left by other visible columns.
            "Mod+G" = basicAction "expand-column-to-available-width";
            "Mod+Comma" = basicAction "consume-or-expel-window-left";
            "Mod+Period" = basicAction "consume-or-expel-window-right";
            # Reorder columns within the workspace strip (swap with neighbor).
            "Mod+Ctrl+H" = basicAction "move-column-left";
            "Mod+Ctrl+L" = basicAction "move-column-right";

            # Workspaces
            "Mod+1" = action "focus-workspace" 1;
            "Mod+2" = action "focus-workspace" 2;
            "Mod+3" = action "focus-workspace" 3;
            "Mod+4" = action "focus-workspace" 4;
            "Mod+5" = action "focus-workspace" 5;
            "Mod+6" = action "focus-workspace" 6;
            "Mod+7" = action "focus-workspace" 7;
            "Mod+8" = action "focus-workspace" 8;
            "Mod+9" = action "focus-workspace" 9;

            "Mod+Shift+1" = action "move-column-to-workspace" 1;
            "Mod+Shift+2" = action "move-column-to-workspace" 2;
            "Mod+Shift+3" = action "move-column-to-workspace" 3;
            "Mod+Shift+4" = action "move-column-to-workspace" 4;
            "Mod+Shift+5" = action "move-column-to-workspace" 5;
            "Mod+Shift+6" = action "move-column-to-workspace" 6;
            "Mod+Shift+7" = action "move-column-to-workspace" 7;
            "Mod+Shift+8" = action "move-column-to-workspace" 8;
            "Mod+Shift+9" = action "move-column-to-workspace" 9;

            # Column sizing
            "Mod+R" = basicAction "switch-preset-column-width";
            # Width presets: Narrow / Split / Wide (Full lives on Mod+F).
            "Mod+N" = columnWidth "33.3333%";
            "Mod+S" = columnWidth "50%";
            "Mod+W" = columnWidth "66.6666%";
            "Mod+Minus" = columnWidth "-10%";
            "Mod+Equal" = columnWidth "+10%";

            # Window heights / distribution within a column
            "Mod+Shift+R" = basicAction "switch-preset-window-height";
            "Mod+Shift+K" = basicAction "move-window-up";
            "Mod+Shift+J" = basicAction "move-window-down";
            "Mod+Shift+Minus" = columnHeight "-10%";
            "Mod+Shift+Equal" = columnHeight "+10%";
            "Mod+Tab".focus-workspace-down = { };
            "Mod+Shift+Tab".focus-workspace-up = { };

            "Mod+X" = _: {
              props.repeat = false;
              content.toggle-overview = { };
            };
            "Mod+T".toggle-column-tabbed-display = { };
            # Tabs: previous tab + jump to tab N within the focused column.
            "Mod+P" = basicAction "focus-window-previous";
            "Mod+Alt+1" = action "focus-window-in-column" 1;
            "Mod+Alt+2" = action "focus-window-in-column" 2;
            "Mod+Alt+3" = action "focus-window-in-column" 3;
            "Mod+Alt+4" = action "focus-window-in-column" 4;
            "Mod+Alt+5" = action "focus-window-in-column" 5;
            "Mod+Alt+6" = action "focus-window-in-column" 6;
            "Mod+Alt+7" = action "focus-window-in-column" 7;
            "Mod+Alt+8" = action "focus-window-in-column" 8;
            "Mod+Alt+9" = action "focus-window-in-column" 9;
            "Mod+Shift+H".focus-monitor-left = { };
            "Mod+Shift+L".focus-monitor-right = { };
            "Mod+Shift+S" = basicAction "screenshot";
            "Mod+Shift+Slash".show-hotkey-overlay = { };
          };
      };
    };

  # NixOS side: pull in the wayland layer (greetd + tuigreet live there), then
  # install the *wrapped* niri into the system profile. That package ships the
  # wayland-session .desktop, the niri-session helper, and a niri.service whose
  # ExecStart points back at the wrapped binary (so NIRI_CONFIG — and thus the
  # whole config, including this host's outputs — applies). Putting it in
  # systemPackages is what makes the session show up in the greeter
  # (/run/current-system/sw/share/wayland-sessions).
  flake.modules.nixos.niri =
    { config, pkgs, ... }:
    {
      imports = [ flake.modules.nixos.desktop-wayland ];

      options.desktop = {
        outputs = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Per-host niri output (monitor) configuration.";
        };
        workspaces = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Per-host niri named-workspace pinning.";
        };
      };

      config = {
        environment.systemPackages = [
          pkgs.xwayland-satellite
          (flake.wrappers.niri.wrap {
            inherit pkgs;
            settings = {
              outputs = config.desktop.outputs;
              workspaces = config.desktop.workspaces;
            };
          })
        ];
        xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
        # niri spawns polkit-gnome at startup; it needs the polkit daemon.
        security.polkit.enable = true;
      };
    };

  flake.modules.homeManager.niri =
    { pkgs, lib, ... }:
    {
      imports = [
        flake.modules.homeManager.desktop-wayland
        # noctalia 5.x via its upstream home-manager module (programs.noctalia).
        flake.modules.homeManager.noctalia
      ];

      # niri itself comes from the system profile (above). The session shell
      # (noctalia bar, installed by the noctalia module above) and the lock
      # screen are per-user.
      home.packages = [
        (flake.wrappers.swaylock.wrap { inherit pkgs; })
      ];

      # Live-apply config changes to a running niri after `nixos-rebuild
      # switch`. niri only watches the immutable store path it was started
      # with, so it never auto-reloads. The wrapped niri.service ships an
      # ExecReload that runs `niri msg action load-config-file` against the
      # freshly-built config, so we just trigger a reload once per switch
      # (guarded so it's a no-op when no niri session is running). Runs after
      # the user daemon picks up the new unit definition.
      home.activation.reloadNiri = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
        if ${lib.getExe' pkgs.systemd "systemctl"} --user is-active --quiet niri.service; then
          run ${lib.getExe' pkgs.systemd "systemctl"} --user reload niri.service || true
        fi
      '';
    };
}
