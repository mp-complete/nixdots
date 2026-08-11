{
  repo.aspects.playwright =
    { pkgs, ... }:
    {
      runtimeLibraries = with pkgs; [
        alsa-lib
        at-spi2-core
        cairo
        cups
        dbus
        expat
        fontconfig
        freetype
        glib
        gtk3
        libdrm
        libgbm
        libxkbcommon
        nspr
        nss
        pango
        udev
        libx11
        libxcomposite
        libxcursor
        libxdamage
        libxext
        libxfixes
        libxi
        libxrandr
        libxrender
        libxtst
        libxcb
      ];
    };
}
