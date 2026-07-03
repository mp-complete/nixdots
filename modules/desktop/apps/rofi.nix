{ config, lib, ... }:
let
  # Rasi literals: colors, variable refs (@name) and dimensions must be emitted
  # unquoted, unlike plain strings which the wrapper wraps in double quotes.
  lit = value: {
    _type = "literal";
    inherit value;
  };

  # Catppuccin Macchiato palette (matches kitty's Catppuccin-Macchiato theme
  # and the kitty tab-bar accent #ed8796).
  palette = {
    base = "#24273a";
    mantle = "#1e2030";
    crust = "#181926";
    text = "#cad3f5";
    subtext0 = "#a5adcb";
    surface0 = "#363a4f";
    surface1 = "#494d64";
    overlay0 = "#6e738d";
    blue = "#8aadf4";
    mauve = "#c6a0f6";
    red = "#ed8796";
  };
in
{
  flake.wrappers.rofi =
    { pkgs, wlib, ... }:
    {
      imports = [ wlib.wrapperModules.rofi ];
      settings = {
        show-icons = true;
        icon-theme = "Papirus-Dark";
        display-drun = " ";
        drun-display-format = "{name}";
        terminal = config.terminal.command;
      };

      theme = {
        "*" = {
          bg-col = lit palette.base;
          bg-col-light = lit palette.surface0;
          border-col = lit palette.mauve;
          selected-col = lit palette.surface1;
          accent = lit palette.blue;
          accent-alt = lit palette.red;
          fg-col = lit palette.text;
          fg-col2 = lit palette.subtext0;
          grey = lit palette.overlay0;
          width = 600;
          font = "DepartureMono Nerd Font 12";
        };

        "element-text, element-icon, mode-switcher" = {
          background-color = lit "inherit";
          text-color = lit "inherit";
        };

        window = {
          height = lit "360px";
          border = lit "2px";
          border-color = lit "@border-col";
          background-color = lit "@bg-col";
          border-radius = lit "10px";
        };

        mainbox = {
          background-color = lit "@bg-col";
        };

        inputbar = {
          children = lit "[prompt,entry]";
          background-color = lit "@bg-col";
          border-radius = lit "6px";
          padding = lit "2px";
        };

        prompt = {
          background-color = lit "@accent";
          padding = lit "6px";
          text-color = lit "@bg-col";
          border-radius = lit "4px";
          margin = lit "5px 0px 0px 5px";
        };

        textbox-prompt-colon = {
          expand = false;
          str = ":";
        };

        entry = {
          padding = lit "6px";
          margin = lit "5px 5px 0px 5px";
          text-color = lit "@fg-col";
          background-color = lit "@bg-col-light";
          border-radius = lit "4px";
        };

        listview = {
          border = lit "0px 0px 0px";
          padding = lit "6px 0px 0px";
          margin = lit "5px 5px 5px 5px";
          columns = 1;
          background-color = lit "@bg-col";
        };

        element = {
          padding = lit "6px";
          background-color = lit "@bg-col";
          text-color = lit "@fg-col";
          border-radius = lit "4px";
        };

        "element-icon" = {
          size = lit "18px";
        };

        "element selected" = {
          background-color = lit "@selected-col";
          text-color = lit "@fg-col";
        };

        "mode-switcher" = {
          spacing = 0;
        };

        "button" = {
          padding = lit "10px";
          background-color = lit "@bg-col-light";
          text-color = lit "@grey";
          vertical-align = lit "0.5";
          horizontal-align = lit "0.5";
        };

        "button selected" = {
          background-color = lit "@bg-col";
          text-color = lit "@accent";
        };
      };
    };
}
