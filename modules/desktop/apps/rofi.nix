{ config, ... }:
{
  flake.wrappers.rofi = { pkgs, wlib, ... }: {
    imports = [ wlib.wrapperModules.rofi ];
    settings = {
      show-icons = true;
      icon-theme = "Papirus-Dark";
      display-drun = " ";
      drun-display-format = "{name}";
      terminal = config.terminal.command;
    };
  };
}
