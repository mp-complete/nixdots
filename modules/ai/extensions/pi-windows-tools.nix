{ lib, ... }:
{
  # @bacnh85/pi-windows-tools — Windows-native shell execution, path
  # conversion, WSL bridging, safety checks, and developer-tool discovery.
  # https://github.com/bacnh85/pi-extensions/tree/main/pi-windows-tools
  pi.extensions.pi-windows-tools = {
    pname = "@bacnh85/pi-windows-tools";
    version = "0.5.2";
    hash = "sha512-TwM7zHA4IF5QXhpfM9Oj1WaLLRxIOYobdivcurH7toXSwcZBGPXndeDQuUu0EFh6zB4xTMOHIt4MtFJZs43I7A==";
    meta.platforms = lib.platforms.linux; # Enabled only by the pi-wsl wrapper
  };
}
