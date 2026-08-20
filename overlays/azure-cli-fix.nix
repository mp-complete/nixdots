# Temporary overlay: pull azure-cli from pinned nixpkgs master
# Fixes: https://github.com/NixOS/nixpkgs/issues/493712
# Remove once nixos-unstable includes azure-cli >= 2.82.0
{ nixpkgs-master }:
final: prev:
let
  # `prev.system` is a deprecated nixpkgs alias; the platform string now lives
  # on stdenv.hostPlatform.
  pkgs-master = import nixpkgs-master { inherit (prev.stdenv.hostPlatform) system; };
in
{
  inherit (pkgs-master) azure-cli;
}
