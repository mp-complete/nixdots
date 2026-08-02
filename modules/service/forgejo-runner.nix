{ lib, config, ... }:
let
  # Reuse the self-hosted Forgejo URL that git.nix already knows about.
  instanceUrl = lib.head config.git.forgejoUrls;
in
{
  # Opt-in: hosts that act as a Forgejo Actions runner import `forgejo-runner`.
  #
  # Registration token: create one in Forgejo (site/org/repo → Actions → Runners
  # → "Create new runner"), then store it under the `forgejo-runner-token` key in
  # secrets/general.yaml. Changing the token or the labels below forces the
  # service to re-register on next start.
  flake.modules.nixos.forgejo-runner =
    { pkgs, config, ... }:
    {
      # Container-based jobs (`runs-on: ubuntu-latest`) need a runtime.
      virtualisation.docker.enable = true;

      sops.secrets.forgejo-runner-token = {
        sopsFile = ../../secrets/general.yaml;
        key = "forgejo-runner-token";
      };

      # The gitea-actions-runner module consumes `tokenFile` as a systemd
      # EnvironmentFile, so it must define TOKEN= rather than hold the bare
      # token. Render that wrapper from the secret. systemd (as root) reads it
      # before dropping to the DynamicUser, so root-only 0400 is fine.
      sops.templates."forgejo-runner.env".content = ''
        TOKEN=${config.sops.placeholder.forgejo-runner-token}
      '';

      services.gitea-actions-runner = {
        package = pkgs.forgejo-runner;
        instances.${config.networking.hostName} = {
          enable = true;
          name = config.networking.hostName;
          url = instanceUrl;
          tokenFile = config.sops.templates."forgejo-runner.env".path;
          labels = [
            # Docker-backed labels: the workflow's `runs-on` value picks one.
            "ubuntu-latest:docker://node:20-bookworm"
            "docker:docker://node:20-bookworm"
            # Native label: jobs run directly on this host (nix available).
            "native:host"
          ];
          # PATH for `:host` jobs. DynamicUser `gitea-runner` runs them, so nix
          # builds go through the daemon as an unprivileged user.
          hostPackages = with pkgs; [
            bash
            coreutils
            curl
            gawk
            git
            gnugrep
            gnused
            gnutar
            gzip
            jq
            nix
            nodejs
            openssh
            wget
            xz
          ];
        };
      };
    };
}
