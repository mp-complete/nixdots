# pi comes from lukasl-dev/pi.nix (`inputs.pi-nix`).
#
# The package itself is built with *our* nixpkgs so pi shares the host's
# nodejs closure, and with our own version data so it tracks v0.84.3 rather
# than the input's v0.84.2 — see pkgs/pi for the details and the update recipe.
#
# `pkgs.pi-coding-agent` is the name pi.nix's own overlay uses, so consumers
# read the same either way; modules/ai/pi.nix wraps it.
{ pi-nix }:
final: _prev: {
  pi-coding-agent = final.callPackage ../pkgs/pi { inherit pi-nix; };
}
