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

        # Splits moved to the Ctrl+a leader (leader+% / leader+"), see
        # extraConfig below. Removing the old kitty_mod+backslash / kitty_mod+minus
        # bindings restores kitty's defaults for those keys (notably
        # kitty_mod+minus = decrease_font_size).

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
      extraConfig = ''
        map --new-mode leader --on-action end --on-unknown end ctrl+a
        map --mode leader ctrl+a send_key ctrl+a
        map --mode leader g launch --type=overlay --cwd=current ${pkgs.lazygit}/bin/lazygit
        map --mode leader z toggle_layout stack
        map --mode leader r start_resizing_window
        map --mode leader c launch --type=tab --cwd=current
        map --mode leader x close_tab
        map --mode leader shift+5 launch --location=vsplit --cwd=current
        map --mode leader shift+apostrophe launch --location=hsplit --cwd=current
        ${lib.concatMapStringsSep "\n" (n: "map --mode leader ${toString n} goto_tab ${toString n}") (lib.range 1 9)}
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
