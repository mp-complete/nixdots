# Cheap validation for the `pi-agent` bucket, which no host imports yet.
#
# Evaluates a throwaway NixOS system with the bucket + a job switched on and
# forces the parts that actually break: assertions, generated unit text, and
# the runner scripts (whose derivation runs shellcheck).
#
#   nix build .#checks.x86_64-linux.pi-agent-eval
#
# The same eval exposes each job's runner as a package, which is the phase-1
# test path — run one by hand, no systemd, no root:
#
#   nix build .#pi-agent-runner-nixdots-docs
#   PI_AGENT_STATE_DIR=$PWD/state ./result/bin/pi-agent-nixdots-docs
{ inputs, config, ... }:
{
  perSystem =
    {
      system,
      lib,
      pkgs,
      ...
    }:
    let
      host = inputs.nixpkgs.lib.nixosSystem {
        modules = [
          config.flake.modules.nixos.pi-agent
          inputs.sops-nix.nixosModules.sops
          (
            { lib, ... }:
            {
              # perSystem `pkgs` already carries the overlays that hosts get
              # via the `base` bucket (modules/flake/package-set.nix).
              nixpkgs.pkgs = pkgs;
              # Skips bootloader/fileSystems requirements; we never build the
              # toplevel, only the units.
              boot.isContainer = true;
              system.stateVersion = "25.05";
              sops.age.keyFile = "/etc/nixos/keys.txt";

              # Exercise the sops/environmentFile path of the worked example.
              piAgent.jobs.nixdots-docs.enable = lib.mkForce true;

              # …and a repo-less, manual-only job, the other shape.
              piAgent.jobs.sample-repoless = {
                description = "pi-agent eval sample";
                prompt = "Print the current date and stop.";
                tools = [ "bash" ];
              };
            }
          )
        ];
      };

      # NB: do not name this `pkgs` — it would shadow the perSystem arg used
      # above for `nixpkgs.pkgs` and make the nixos eval self-referential.
      hostPkgs = host.pkgs;

      failed = lib.filter (a: !a.assertion) host.config.assertions;

      units =
        lib.mapAttrsToList (n: _: host.config.systemd.units."${n}.service".text) (
          lib.filterAttrs (n: _: lib.hasPrefix "pi-agent-" n) host.config.systemd.services
        )
        ++ lib.mapAttrsToList (n: _: host.config.systemd.units."${n}.timer".text) (
          lib.filterAttrs (n: _: lib.hasPrefix "pi-agent-" n) host.config.systemd.timers
        );

      runners = host.config.piAgent.runners;
    in
    {
      checks.pi-agent-eval =
        lib.throwIf (failed != [ ])
          "pi-agent assertions failed: ${lib.concatMapStringsSep "; " (a: a.message) failed}"
          (
            hostPkgs.runCommand "pi-agent-eval" { } ''
              mkdir -p "$out"
              cp ${hostPkgs.writeText "pi-agent-units" (lib.concatStringsSep "\n" units)} "$out/units.txt"
              ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: r: ''ln -s ${r} "$out/runner-${n}"'') runners)}
            ''
          );

      packages = lib.mapAttrs' (n: r: lib.nameValuePair "pi-agent-runner-${n}" r) runners;
    };
}
