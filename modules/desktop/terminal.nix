{ lib, ... }:
{
  # Single source of truth for the default terminal emulator. WMs and launchers
  # read these instead of hardcoding a name, so switching terminals is one edit.
  options.terminal = {
    command = lib.mkOption {
      type = lib.types.str;
      default = "kitty";
      description = ''
        Bare command used to launch the default terminal (resolved on the
        session PATH). Read by i3, niri, rofi, etc.
      '';
    };
    exec = lib.mkOption {
      type = lib.types.str;
      default = "kitty -e";
      description = ''
        Command prefix used to run a program in a new terminal window, e.g.
        `kitty -e yazi`. kitty uses the `-e` convention for running a
        program in a new window.
      '';
    };
  };
}
