{
  flake.wrappers.swaylock = { pkgs, wlib, ... }: {
    imports = [ wlib.wrapperModules.swaylock ];
    package = pkgs.swaylock-effects;
    settings = {
      clock = true;
      timestr = "%I:%M %p";
      datestr = "%A, %B %d";

      screenshots = true;
      effect-blur = "10x4";
      effect-vignette = "0.5:0.5";
      fade-in = 0.2;

      font = "DepartureMono Nerd Font";
      font-size = 20;

      indicator = true;
      indicator-radius = 100;
      indicator-thickness = 7;
      indicator-caps-lock = true;

      inside-color = "24273acc";
      inside-clear-color = "24273acc";
      inside-ver-color = "8aadf4cc";
      inside-wrong-color = "ed8796cc";

      ring-color = "c6a0f6ff";
      ring-clear-color = "a6da95ff";
      ring-ver-color = "8aadf4ff";
      ring-wrong-color = "ed8796ff";

      key-hl-color = "8aadf4ff";
      bs-hl-color = "ed8796ff";

      line-color = "00000000";
      line-clear-color = "00000000";
      line-ver-color = "00000000";
      line-wrong-color = "00000000";

      separator-color = "00000000";

      text-color = "cad3f5ff";
      text-clear-color = "cad3f5ff";
      text-ver-color = "cad3f5ff";
      text-wrong-color = "cad3f5ff";

      text-caps-lock-color = "f5a97fff";
    };
  };
}
