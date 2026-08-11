{
  # AI agents subsystem. Option namespace (`my.ai.*`) kept as-is for now —
  # its final naming was deferred (decision pass). Implementation files live
  # in ./_impl (ported verbatim from the old config) and merge into the `ai`
  # home-manager bucket.
  flake.modules.homeManager.ai =
    { pkgs, ... }:
    {
      imports = [
        ./_impl/options.nix
        ./_impl/secrets.nix
        ./_impl/opencode.nix
        ./_impl/copilot-cli.nix
        ./_impl/aider.nix
      ];

      home.packages = [ pkgs.llm-agents.hunk ];
    };
}
