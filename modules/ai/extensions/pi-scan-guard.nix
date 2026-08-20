{ ... }:
{
  # pi-scan-guard — blocks unbounded filesystem scans (`find /`,
  # `rg /nix/store`, `fd /mnt/c`, …) before the bash tool runs them.
  #
  # These hosts are WSL with `/mnt/c` mounted, so a scan rooted at `/` walks
  # the whole Windows filesystem and hangs. Depth-bounded scans and scans
  # rooted at a specific directory pass through untouched; see
  # `_local/pi-scan-guard/src/detect.mjs` for the exact rules.
  #
  # Interactive variants prompt (there are rare legitimate cases); the
  # headless daemon hard-blocks, since nothing is there to approve.
  pi.extensions.pi-scan-guard = {
    pname = "pi-scan-guard";
    version = "0.1.0";
    build = { pkgs, ... }: pkgs.callPackage ./_local/pi-scan-guard { };
  };
}
