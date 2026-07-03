{
  flake.wrappers.dunst =
    {
      pkgs,
      wlib,
      config,
      ...
    }:
    let
      mkIniSection =
        name: attrs:
        "[${name}]\n"
        + builtins.concatStringsSep "\n" (
          builtins.attrValues (builtins.mapAttrs (k: v: "    ${k} = ${builtins.toString v}") attrs)
        )
        + "\n";

      dunstrc = builtins.concatStringsSep "\n" [
        (mkIniSection "global" {
          width = "(300, 400)";
          height = "(0, 250)";
          offset = ''"12x12"'';
          origin = "top-right";
          notification_limit = 5;
          corner_radius = 14;
          frame_width = 2;
          frame_color = ''"#c6a0f6"'';
          separator_height = 2;
          separator_color = ''"#363a4f"'';
          gap_size = 6;
          background = ''"#24273a"'';
          foreground = ''"#cad3f5"'';
          transparency = 0;
          font = ''"DepartureMono Nerd Font 11"'';
          markup = "full";
          format = ''"<b>%s</b>\n%b"'';
          alignment = "left";
          vertical_alignment = "center";
          word_wrap = true;
          ellipsize = "end";
          padding = 14;
          horizontal_padding = 16;
          text_icon_padding = 14;
          icon_position = "left";
          min_icon_size = 48;
          max_icon_size = 64;
          icon_theme = "Papirus-Dark";
          enable_recursive_icon_lookup = true;
          progress_bar = true;
          progress_bar_height = 8;
          progress_bar_frame_width = 1;
          progress_bar_min_width = 250;
          progress_bar_max_width = 350;
          progress_bar_corner_radius = 4;
          sort = true;
          indicate_hidden = true;
          show_age_threshold = 30;
          stack_duplicates = true;
          hide_duplicate_count = false;
          show_indicators = true;
          sticky_history = true;
          history_length = 50;
          ignore_dbusclose = false;
          mouse_left_click = "close_current";
          mouse_middle_click = "close_all";
          mouse_right_click = ''"do_action, close_current"'';
        })
        (mkIniSection "urgency_low" {
          background = ''"#24273a"'';
          foreground = ''"#b8c0e0"'';
          frame_color = ''"#494d64"'';
          highlight = ''"#c6a0f6"'';
          timeout = 5;
        })
        (mkIniSection "urgency_normal" {
          background = ''"#24273a"'';
          foreground = ''"#cad3f5"'';
          frame_color = ''"#c6a0f6"'';
          highlight = ''"#c6a0f6"'';
          timeout = 8;
        })
        (mkIniSection "urgency_critical" {
          background = ''"#24273a"'';
          foreground = ''"#cad3f5"'';
          frame_color = ''"#ed8796"'';
          highlight = ''"#ed8796"'';
          timeout = 0;
        })
      ];
    in
    {
      imports = [ wlib.modules.default ];
      package = pkgs.dunst;

      constructFiles.generatedConfig = {
        relPath = "dunstrc";
        content = dunstrc;
      };

      flags."--config" = config.constructFiles.generatedConfig.path;
    };
}
