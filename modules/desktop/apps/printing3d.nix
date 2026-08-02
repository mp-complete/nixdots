{
  # 3D printing / CAD (euler workstation). Opt-in: hosts import `printing3d`.
  flake.modules.homeManager.printing3d =
    { pkgs, ... }:
    let
      # OrcaSlicer (wxWidgets/GTK3) renders a black/blank 3D viewport and can
      # crash on wlroots Wayland (niri) + NVIDIA. Force it through XWayland.
      # WEBKIT_DISABLE_COMPOSITING_MODE is already set by the upstream wrapper.
      orca-slicer-x11 = pkgs.symlinkJoin {
        name = "orca-slicer-x11";
        paths = [ pkgs.orca-slicer ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/orca-slicer \
            --set GDK_BACKEND x11
        '';
      };
    in
    {
      home.packages = [
        orca-slicer-x11
        pkgs.freecad-wayland
      ];
    };
}
