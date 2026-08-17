{ ... }:
{
  # agent-browser-edge-bridge — local (non-npm) pi extension. Routes the
  # WSL-only pi-chrome-use tool exclusively to a dedicated Windows Edge profile.
  # Source lives under ./_local (a `/_` path, so not auto-imported as a
  # flake-parts module); built via callPackage.
  pi.extensions.agent-browser-edge-bridge = {
    pname = "agent-browser-edge-bridge";
    version = "0.3.0";
    # No npm tarball: leave hash empty and build from the local source.
    build = { pkgs, ... }: pkgs.callPackage ./_local/agent-browser-edge-bridge { };
  };
}
