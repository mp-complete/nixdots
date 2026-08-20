{ ... }:
{
  # pi-file-tools — turns on pi's built-in `find`, `grep` and `ls` tools,
  # which ship with pi but are off by default (the default active set is
  # read/bash/edit/write).
  #
  # This is the structural half of the "stop shelling out to find" fix:
  # while those three are disabled, pi's own system prompt tells the model
  # "Use bash for file operations like ls, rg, find". Enabling them removes
  # that line and hands the model an fd-backed, gitignore-aware, truncating
  # `find` instead. pi-scan-guard remains the backstop for bash.
  pi.extensions.pi-file-tools = {
    pname = "pi-file-tools";
    version = "0.1.0";
    build = { pkgs, ... }: pkgs.callPackage ./_local/pi-file-tools { };
  };
}
