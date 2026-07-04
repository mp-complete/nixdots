{ self, config, ... }:
{
  flake.wrappers.kitty =
    {
      pkgs,
      wlib,
      config,
      lib,
      ...
    }:
    {
      imports = [ wlib.wrapperModules.kitty ];
      package = pkgs.kitty;
      themeFile = "Catppuccin-Macchiato";
      font = {
        name = "DepartureMono Nerd Font";
      };
      settings = {
        confirm_os_window_close = 0;
        scrollback_lines = 50000;
        enable_audio_bell = false;
        update_check_interval = 0;
        clipboard_control = "write-clipboard write-primary";
        strip_trailing_spaces = "smart";

        # Soft, slow "pulsing" cursor: the easing function makes the blink fade
        # in/out smoothly instead of a hard on/off flip, and the longer interval
        # slows the whole cycle down. Keep blinking indefinitely (don't stop
        # after idle).
        cursor_blink_interval = "0.8 ease-in-out";
        cursor_stop_blinking_after = 0;

        # Window transparency + blur. Now that niri no longer fills the border
        # color behind kitty (see draw-border-with-background rule in niri.nix),
        # the wallpaper shows through. Blur uses the generic Wayland
        # `ext-background-effect-v1` protocol, which niri 26.04 implements and
        # kitty 0.46+ drives. dynamic_background_opacity lets us tweak opacity
        # live (ctrl+shift+a > / < by default).
        background_opacity = "0.8";
        dynamic_background_opacity = true;
        background_blur = 64;

        # Smooth cursor motion: the cursor animates to its new position leaving a
        # short trail instead of teleporting. cursor_trail is the "start" threshold
        # (px) before the trail kicks in; keep it small so short hops still animate.
        cursor_trail = 3;
        cursor_trail_decay = "0.1 0.4";

        # A little breathing room around the text.
        window_padding_width = 8;

        # Fade unfocused splits so the active pane stands out.
        inactive_text_alpha = "0.4";

        # Editor-style link styling.
        url_style = "curly";

        # Subtle, silent visual bell: a quick eased flash instead of a sound.
        visual_bell_duration = "0.15 ease-in-out";
        window_alert_on_bell = true;

        # Cleaner, borderless windows (WM handles move/close).
        hide_window_decorations = true;

        # Slightly roomier line height for readability.
        modify_font = "cell_height 115%";

        # lualine-style status bar: kitty's tab bar is fully programmable, so we
        # drive it from tab_bar.py (shipped below). `custom` style + min_tabs=1
        # keeps it always visible; templates handle the per-tab (left) titles.
        tab_bar_style = "custom";
        tab_bar_edge = "bottom";
        tab_bar_align = "left";
        tab_bar_min_tabs = 1;
        tab_powerline_style = "angled";
        tab_title_template = "{index}: {title}";
        active_tab_title_template = "{fmt.bold}{index}: {title}{fmt.nobold}";
      };

      # Ship the status-bar script next to kitty.conf and point kitty's config
      # directory at it so `tab_bar_style custom` finds tab_bar.py. Keeping the
      # Python in its own file avoids Nix-string escaping and stays lintable.
      constructFiles.tabBar = {
        relPath = "tab_bar.py";
        content = builtins.readFile ./kitty-tab-bar.py;
      };
      env.KITTY_CONFIG_DIRECTORY = builtins.dirOf config.constructFiles.kittyConfig.path;
      keybindings = {
        # Command palette
        "kitty_mod+x" = "command_palette";

        # Pane navigation (tmux-like vim keys)
        "kitty_mod+h" = "neighboring_window left";
        "kitty_mod+j" = "neighboring_window down";
        "kitty_mod+k" = "neighboring_window up";
        "kitty_mod+l" = "neighboring_window right";

        # Pane navigation with arrows
        "kitty_mod+left" = "neighboring_window left";
        "kitty_mod+down" = "neighboring_window down";
        "kitty_mod+up" = "neighboring_window up";
        "kitty_mod+right" = "neighboring_window right";

        # Window creation
        "kitty_mod+return" = "launch --cwd current";

        # Layout switching
        "kitty_mod+space" = "next_layout";
        "kitty_mod+tab" = "last_used_layout";
        "kitty_mod+1" = "goto_layout splits";
        "kitty_mod+2" = "goto_layout tall";
        "kitty_mod+3" = "goto_layout fat";
        "kitty_mod+4" = "goto_layout grid";
      };

      # ── Ctrl+a leader (tmux-style modal keymap) ──────────────────────────
      # Ctrl+a enters the one-shot "leader" mode: the next key runs ONE action
      # then exits (--on-action end). Any unmapped key exits and passes through
      # (--on-unknown end), so Esc cancels. Pressing Ctrl+a again (leader then
      # Ctrl+a) sends a real Ctrl+a to the focused program via send_key -> e.g.
      # <C-a> in nvim / start-of-line in the shell (tmux send-prefix). The active
      # mode name shows as a LEADER lamp in the status bar (tab_bar.py reads
      # mappings.current_keyboard_mode_name).
      #   leader Ctrl+a  send a literal Ctrl+a to the pane (<C-a> in nvim)
      #   leader+g  lazygit in an overlay (popup) window, in the current cwd
      #   leader+z  zoom the active window (toggle the stack layout)
      #   leader+r  interactive resize mode (arrows/hjkl, Enter/Esc to finish)
      #   leader+c  new tab in the current cwd
      #   leader+x  close the current tab
      #   leader+%  vertical split   (US layout: shift+5)
      #   leader+"  horizontal split (US layout: shift+apostrophe)
      #   leader+1..9  switch to tab 1..9
      extraConfig =
        let
          leader = "ctrl+a";
        in
        ''
          map --new-mode leader --on-action end --on-unknown end ${leader}
          map --mode leader ${leader} send_key ${leader}
          map --mode leader g launch --type=tab --cwd=current ${pkgs.lazygit}/bin/lazygit
          map --mode leader z toggle_layout stack
          map --mode leader r start_resizing_window
          map --mode leader c launch --type=tab --cwd=current
          map --mode leader x close_tab
          map --mode leader shift+5 launch --location=vsplit --cwd=current
          map --mode leader shift+apostrophe launch --location=hsplit --cwd=current
          ${lib.concatMapStringsSep "\n" (n: "map --mode leader ${toString n} goto_tab ${toString n}") (
            lib.range 1 9
          )}
        '';
    };

  flake.modules.nixos.desktop-core =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        (config.flake.wrappers.kitty.wrap { inherit pkgs; })
      ];
    };
}
