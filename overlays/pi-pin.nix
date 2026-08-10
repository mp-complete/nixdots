# Temporary overlay: hold pi-coding-agent at 0.83.0.
# Newer releases (0.84.x) trigger frequent HTTP 429 rate-limit errors.
# Remove this overlay (and the `llm-agents-pinned` flake input) once upstream
# resolves that, letting `llm-agents` track its own latest pi again.
#
# The pinned llm-agents.nix revision carries the version-coupled files pi's
# build needs (`hashes.json` + `package-lock.json`), so applying its
# `shared-nixpkgs` overlay against our `final` yields a 0.83.0 pi built with
# our nixpkgs. Only `pi` is taken; every other llm-agents package stays on the
# tracked input.
{ llm-agents-pinned }:
final: prev: {
  llm-agents = prev.llm-agents // {
    inherit ((llm-agents-pinned.overlays.shared-nixpkgs final prev).llm-agents) pi;
  };
}
