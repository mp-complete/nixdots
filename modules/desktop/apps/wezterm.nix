{ config, ... }:
{
  # The everyday terminal (installed via desktop-core, exposed as `.#wezterm`).
  # Promoted from the wezterm-tour experiment: tmux-style leader, rich pane/tab/
  # workspace control, live config overrides, and tiling-WM-friendly chrome.
  flake.wrappers.wezterm =
    {
      pkgs,
      wlib,
      ...
    }:
    {
      imports = [ wlib.wrapperModules.wezterm ];
      package = pkgs.wezterm;

      "wezterm.lua".content = # lua
        ''
          local wezterm = require 'wezterm'
          local act = wezterm.action
          local config = wezterm.config_builder()

          ----------------------------------------------------------------------
          -- Runtime override toggles (window:set_config_overrides)
          ----------------------------------------------------------------------
          local function toggle_opacity(window)
            local o = window:get_config_overrides() or {}
            if o.window_background_opacity == nil then
              o.window_background_opacity = 0.75
            elseif o.window_background_opacity > 0.6 then
              o.window_background_opacity = 0.45
            else
              o.window_background_opacity = nil
            end
            window:set_config_overrides(o)
          end

          local function toggle_theme(window)
            local o = window:get_config_overrides() or {}
            if o.color_scheme == 'Catppuccin Latte' then
              o.color_scheme = nil
            else
              o.color_scheme = 'Catppuccin Latte'
            end
            window:set_config_overrides(o)
            window:toast_notification('wezterm', 'theme -> ' .. (o.color_scheme or 'Catppuccin Macchiato'), nil, 1500)
          end

          local function toggle_ligatures(window)
            local o = window:get_config_overrides() or {}
            if o.harfbuzz_features == nil then
              o.harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' }
              window:toast_notification('wezterm', 'ligatures OFF', nil, 1500)
            else
              o.harfbuzz_features = nil
              window:toast_notification('wezterm', 'ligatures ON', nil, 1500)
            end
            window:set_config_overrides(o)
          end

          -- Cycle the primary font live: DepartureMono -> JetBrains -> Cozette.
          -- State is tracked per-window (config overrides only accept real
          -- config keys, so we can't stash the index in there).
          local font_state = {}
          local font_choices = {
            { font = nil, label = 'DepartureMono' },
            { font = wezterm.font_with_fallback { 'JetBrainsMono Nerd Font', 'Symbols Nerd Font Mono' },
              label = 'JetBrains Mono (ligatures)' },
            { font = wezterm.font_with_fallback { 'CozetteVector', 'Symbols Nerd Font Mono' },
              label = 'Cozette (bitmap)' },
          }
          local function cycle_font(window)
            local id = window:window_id()
            local idx = (font_state[id] or 0) % #font_choices + 1
            font_state[id] = idx
            local choice = font_choices[idx]
            local o = window:get_config_overrides() or {}
            o.font = choice.font
            window:set_config_overrides(o)
            window:toast_notification('wezterm', 'font -> ' .. choice.label, nil, 1500)
          end

          ----------------------------------------------------------------------
          -- Fonts (resolved from the system fontconfig set)
          ----------------------------------------------------------------------
          -- DepartureMono only, no fallback chain: keeps the pixel-font look
          -- consistent (missing glyphs like Nerd Font icons render as tofu).
          config.font = wezterm.font 'DepartureMono Nerd Font'
          config.font_size = 13.0
          config.harfbuzz_features = { 'calt=1', 'clig=1', 'liga=1' }
          config.adjust_window_size_when_changing_font_size = false

          ----------------------------------------------------------------------
          -- Theme & appearance (minimal chrome for tiling WMs like niri)
          ----------------------------------------------------------------------
          config.color_scheme = 'Catppuccin Macchiato'
          config.window_background_opacity = 0.95
          config.text_background_opacity = 1.0
          -- No titlebar, no resize border, no integrated min/max/close buttons.
          config.window_decorations = 'NONE'
          config.integrated_title_buttons = {}
          config.window_padding = { left = 4, right = 4, top = 2, bottom = 2 }
          config.inactive_pane_hsb = { saturation = 0.85, brightness = 0.70 }
          config.default_cursor_style = 'BlinkingBar'
          config.cursor_blink_rate = 600
          config.scrollback_lines = 50000
          config.audible_bell = 'Disabled'
          config.visual_bell = {
            fade_in_duration_ms = 75,
            fade_out_duration_ms = 75,
            target = 'CursorColor',
          }
          config.window_close_confirmation = 'NeverPrompt'
          config.check_for_updates = false

          ----------------------------------------------------------------------
          -- Tab bar (only shown when there's more than one tab)
          ----------------------------------------------------------------------
          config.use_fancy_tab_bar = false
          config.hide_tab_bar_if_only_one_tab = true
          config.tab_bar_at_bottom = false
          config.tab_max_width = 32
          config.show_new_tab_button_in_tab_bar = true

          ----------------------------------------------------------------------
          -- Multiplexing: a local unix domain (try `wezterm connect unix`)
          ----------------------------------------------------------------------
          config.unix_domains = { { name = 'unix' } }

          ----------------------------------------------------------------------
          -- Hyperlinks: defaults + a custom rule turning #1234 into an issue link
          ----------------------------------------------------------------------
          config.hyperlink_rules = wezterm.default_hyperlink_rules()
          table.insert(config.hyperlink_rules, {
            regex = [[#(\d+)\b]],
            format = 'https://github.com/wez/wezterm/issues/$1',
          })

          ----------------------------------------------------------------------
          -- Quick select: extra patterns to one-key-grab
          ----------------------------------------------------------------------
          config.quick_select_patterns = {
            '[0-9a-f]{7,40}',
            '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+',
          }

          ----------------------------------------------------------------------
          -- Keys: start from a clean slate so nothing surprises you. With default
          -- bindings disabled, ONLY the bindings below exist.
          ----------------------------------------------------------------------
          config.disable_default_key_bindings = true

          -- Leader key (tmux-style): Ctrl+a
          config.leader = { key = 'a', mods = 'CTRL', timeout_milliseconds = 1000 }

          config.keys = {
            -- Clipboard
            { key = 'c', mods = 'CTRL|SHIFT', action = act.CopyTo 'Clipboard' },
            { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' },

            -- Splits (in current pane's cwd)
            { key = '\\', mods = 'LEADER', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
            { key = '-', mods = 'LEADER', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },

            -- Lazygit in the current pane's cwd (wezterm has no native floating/
            -- popup panes, so these are the practical substitutes):
            --   LEADER+g  -> new tab in this window (niri leaves the WM alone)
            --   LEADER+G  -> new OS window (niri tiles/places it)
            -- Quitting lazygit exits the pane, closing the tab/window.
            { key = 'g', mods = 'LEADER', action = wezterm.action_callback(function(window, pane)
              local d = pane:get_current_working_dir()
              window:mux_window():spawn_tab {
                args = { '${pkgs.lazygit}/bin/lazygit' },
                cwd = d and d.file_path or nil,
              }
            end) },
            { key = 'G', mods = 'LEADER|SHIFT', action = wezterm.action_callback(function(_, pane)
              local d = pane:get_current_working_dir()
              wezterm.mux.spawn_window {
                args = { '${pkgs.lazygit}/bin/lazygit' },
                cwd = d and d.file_path or nil,
              }
            end) },

            -- Pane navigation (fast: ctrl+shift, and tmux-style: leader)
            { key = 'h', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Left' },
            { key = 'j', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Down' },
            { key = 'k', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Up' },
            { key = 'l', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Right' },
            { key = 'h', mods = 'LEADER', action = act.ActivatePaneDirection 'Left' },
            { key = 'j', mods = 'LEADER', action = act.ActivatePaneDirection 'Down' },
            { key = 'k', mods = 'LEADER', action = act.ActivatePaneDirection 'Up' },
            { key = 'l', mods = 'LEADER', action = act.ActivatePaneDirection 'Right' },

            -- Pane management
            { key = 'z', mods = 'LEADER', action = act.TogglePaneZoomState },
            { key = 'x', mods = 'LEADER', action = act.CloseCurrentPane { confirm = false } },
            { key = ' ', mods = 'LEADER', action = act.RotatePanes 'Clockwise' },
            { key = 'p', mods = 'LEADER', action = act.PaneSelect { alphabet = 'asdfghjkl' } },
            { key = 's', mods = 'LEADER', action = act.PaneSelect { mode = 'SwapWithActive' } },
            { key = 'r', mods = 'LEADER', action = act.ActivateKeyTable {
              name = 'resize_pane', one_shot = false, timeout_milliseconds = 2000 } },

            -- Direct pane resize
            { key = 'LeftArrow', mods = 'CTRL|SHIFT', action = act.AdjustPaneSize { 'Left', 3 } },
            { key = 'DownArrow', mods = 'CTRL|SHIFT', action = act.AdjustPaneSize { 'Down', 3 } },
            { key = 'UpArrow', mods = 'CTRL|SHIFT', action = act.AdjustPaneSize { 'Up', 3 } },
            { key = 'RightArrow', mods = 'CTRL|SHIFT', action = act.AdjustPaneSize { 'Right', 3 } },

            -- Tabs
            { key = 'c', mods = 'LEADER', action = act.SpawnTab 'CurrentPaneDomain' },
            { key = 'n', mods = 'LEADER', action = act.ActivateTabRelative(1) },
            { key = 'b', mods = 'LEADER', action = act.ActivateTabRelative(-1) },
            { key = 'Tab', mods = 'CTRL', action = act.ActivateTabRelative(1) },
            { key = 'Tab', mods = 'CTRL|SHIFT', action = act.ActivateTabRelative(-1) },
            { key = 't', mods = 'CTRL|SHIFT', action = act.SpawnTab 'CurrentPaneDomain' },
            { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentTab { confirm = false } },
            { key = 'n', mods = 'CTRL|SHIFT', action = act.SpawnWindow },
            { key = ',', mods = 'LEADER', action = act.PromptInputLine {
              description = 'Rename tab:',
              action = wezterm.action_callback(function(window, _, line)
                if line then window:active_tab():set_title(line) end
              end),
            } },
            { key = '<', mods = 'LEADER|SHIFT', action = act.MoveTabRelative(-1) },
            { key = '>', mods = 'LEADER|SHIFT', action = act.MoveTabRelative(1) },

            -- Workspaces
            { key = 'w', mods = 'LEADER', action = act.ShowLauncherArgs { flags = 'FUZZY|WORKSPACES' } },
            { key = ']', mods = 'LEADER', action = act.SwitchWorkspaceRelative(1) },
            { key = '[', mods = 'LEADER', action = act.SwitchWorkspaceRelative(-1) },
            { key = 'W', mods = 'LEADER|SHIFT', action = act.PromptInputLine {
              description = 'New workspace name:',
              action = wezterm.action_callback(function(window, pane, line)
                if line and line ~= "" then
                  window:perform_action(act.SwitchToWorkspace { name = line }, pane)
                end
              end),
            } },

            -- Copy / search / select modes
            { key = 'Enter', mods = 'LEADER', action = act.ActivateCopyMode },
            { key = '[', mods = 'CTRL|SHIFT', action = act.ActivateCopyMode },
            { key = 'f', mods = 'CTRL|SHIFT', action = act.Search 'CurrentSelectionOrEmptyString' },
            { key = 'f', mods = 'LEADER', action = act.QuickSelect },
            { key = 'u', mods = 'LEADER', action = act.QuickSelectArgs {
              label = 'open url',
              patterns = { 'https?://\\S+' },
              action = wezterm.action_callback(function(window, pane)
                local url = window:get_selection_text_for_pane(pane)
                if url and url ~= "" then wezterm.open_with(url) end
              end),
            } },
            { key = 'e', mods = 'LEADER', action = act.CharSelect {
              copy_on_select = true, copy_to = 'ClipboardAndPrimarySelection' } },
            { key = 'u', mods = 'CTRL|SHIFT', action = act.CharSelect },

            -- Command palette / launcher / debug
            { key = 'p', mods = 'CTRL|SHIFT', action = act.ActivateCommandPalette },
            { key = 'd', mods = 'LEADER', action = act.ShowDebugOverlay },
            { key = 'L', mods = 'LEADER|SHIFT', action = act.ShowLauncher },

            -- Font size
            { key = '=', mods = 'CTRL', action = act.IncreaseFontSize },
            { key = '-', mods = 'CTRL', action = act.DecreaseFontSize },
            { key = '0', mods = 'CTRL', action = act.ResetFontSize },

            -- Scrollback
            -- NB: ClearScrollback lives on LEADER|SHIFT+K, not CTRL|SHIFT+K.
            -- With key_map_preference = 'Mapped' (the default), a CTRL|SHIFT+'K'
            -- binding shadows the CTRL|SHIFT+'k' "move pane up" binding above,
            -- so Ctrl+Shift+K would clear the scrollback instead of navigating.
            { key = 'K', mods = 'LEADER|SHIFT', action = act.ClearScrollback 'ScrollbackAndViewport' },
            { key = 'PageUp', mods = 'SHIFT', action = act.ScrollByPage(-1) },
            { key = 'PageDown', mods = 'SHIFT', action = act.ScrollByPage(1) },

            -- Live config overrides
            { key = 'o', mods = 'LEADER', action = wezterm.action_callback(toggle_opacity) },
            { key = 't', mods = 'LEADER', action = wezterm.action_callback(toggle_theme) },
            { key = 'I', mods = 'LEADER|SHIFT', action = wezterm.action_callback(toggle_ligatures) },
            { key = 'i', mods = 'LEADER', action = wezterm.action_callback(cycle_font) },

            -- Window
            { key = 'm', mods = 'LEADER', action = act.Hide },
          }

          -- Leader + 1..9 jumps to a tab
          for i = 1, 9 do
            table.insert(config.keys, {
              key = tostring(i),
              mods = 'LEADER',
              action = act.ActivateTab(i - 1),
            })
          end

          ----------------------------------------------------------------------
          -- Modal key table: hold leader+r, then h/j/k/l (or arrows) to resize
          ----------------------------------------------------------------------
          config.key_tables = {
            resize_pane = {
              { key = 'h', action = act.AdjustPaneSize { 'Left', 2 } },
              { key = 'j', action = act.AdjustPaneSize { 'Down', 2 } },
              { key = 'k', action = act.AdjustPaneSize { 'Up', 2 } },
              { key = 'l', action = act.AdjustPaneSize { 'Right', 2 } },
              { key = 'LeftArrow', action = act.AdjustPaneSize { 'Left', 2 } },
              { key = 'DownArrow', action = act.AdjustPaneSize { 'Down', 2 } },
              { key = 'UpArrow', action = act.AdjustPaneSize { 'Up', 2 } },
              { key = 'RightArrow', action = act.AdjustPaneSize { 'Right', 2 } },
              { key = 'Escape', action = 'PopKeyTable' },
              { key = 'Enter', action = 'PopKeyTable' },
            },
          }

          ----------------------------------------------------------------------
          -- Mouse
          ----------------------------------------------------------------------
          config.mouse_bindings = {
            { event = { Up = { streak = 1, button = 'Left' } }, mods = 'CTRL',
              action = act.OpenLinkAtMouseCursor },
            { event = { Down = { streak = 1, button = 'Left' } }, mods = 'CTRL',
              action = act.Nop },
            { event = { Down = { streak = 1, button = 'Right' } }, mods = 'NONE',
              action = act.PasteFrom 'Clipboard' },
          }

          ----------------------------------------------------------------------
          -- Pretty tab titles: "1: nvim *"  (the * marks a zoomed pane)
          ----------------------------------------------------------------------
          wezterm.on('format-tab-title', function(tab, _, _, _, _, max_width)
            local title = tab.tab_title
            if title == nil or #title == 0 then
              title = tab.active_pane.title
            end
            title = wezterm.truncate_right(title, math.max(max_width - 6, 4))
            local zoom = tab.active_pane.is_zoomed and ' *' or ""
            return ' ' .. tostring(tab.tab_index + 1) .. ': ' .. title .. zoom .. ' '
          end)

          ----------------------------------------------------------------------
          -- Status bar: workspace + LEADER lamp left; key-table, battery, clock right
          ----------------------------------------------------------------------
          wezterm.on('update-status', function(window, pane)
            local left = {
              { Background = { Color = '#8aadf4' } },
              { Foreground = { Color = '#24273a' } },
              { Text = ' ' .. window:active_workspace() .. ' ' },
            }
            if window:leader_is_active() then
              table.insert(left, { Background = { Color = '#ed8796' } })
              table.insert(left, { Foreground = { Color = '#24273a' } })
              table.insert(left, { Text = ' LEADER ' })
            end
            window:set_left_status(wezterm.format(left))

            local right = {}
            local kt = window:active_key_table()
            if kt then
              table.insert(right, { Foreground = { Color = '#eed49f' } })
              table.insert(right, { Text = ' [' .. kt .. '] ' })
            end
            for _, b in ipairs(wezterm.battery_info()) do
              table.insert(right, { Foreground = { Color = '#a6da95' } })
              table.insert(right, { Text = string.format(' %.0f%% ', b.state_of_charge * 100) })
            end
            table.insert(right, { Foreground = { Color = '#cad3f5' } })
            table.insert(right, { Text = ' ' .. wezterm.strftime('%a %b %d  %H:%M ') })
            window:set_right_status(wezterm.format(right))
          end)

          return config
        '';
    };

  flake.modules.nixos.desktop-core =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        (config.flake.wrappers.wezterm.wrap { inherit pkgs; })
      ];
    };
}
