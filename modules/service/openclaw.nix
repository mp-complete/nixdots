{ inputs, ... }:
{
  # Opt-in system gateway. Keep OpenClaw in its own OS trust boundary rather
  # than giving an unattended agent Miles's home directory and credentials.
  flake.modules.nixos.openclaw =
    {
      config,
      pkgs,
      ...
    }:
    let
      openclawAdmin = pkgs.writeShellApplication {
        name = "openclaw-admin";
        text = ''
          env_args=(
            "HOME=/var/lib/openclaw"
            "OPENCLAW_CONFIG_PATH=/etc/openclaw/openclaw.json"
            "OPENCLAW_STATE_DIR=/var/lib/openclaw"
            "OPENCLAW_NIX_MODE=1"
            "TERM=''${TERM:-xterm-256color}"
          )
          [[ -n "''${COLORTERM:-}" ]] && env_args+=("COLORTERM=$COLORTERM")
          [[ -n "''${OPENCLAW_THEME:-}" ]] && env_args+=("OPENCLAW_THEME=$OPENCLAW_THEME")

          # The Nix store's sudo binary is intentionally not setuid. Use
          # NixOS's root-owned setuid wrapper instead.
          exec ${config.security.wrapperDir}/sudo -u openclaw --set-home \
            ${pkgs.coreutils}/bin/env "''${env_args[@]}" \
            ${pkgs.openclaw}/bin/openclaw "$@"
        '';
      };

      # Gateway-backed TUI. Do not use `openclaw chat`: that alias implies
      # `tui --local` and would bypass the hardened system gateway.
      openclawTui = pkgs.writeShellApplication {
        name = "openclaw-tui";
        runtimeInputs = [ openclawAdmin ];
        text = ''
          exec openclaw-admin tui "$@"
        '';
      };
    in
    {
      imports = [ inputs.nix-openclaw.nixosModules.openclaw-gateway ];
      nixpkgs.overlays = [ inputs.nix-openclaw.overlays.default ];

      sops.secrets.openclaw-gateway-token = {
        sopsFile = ../../secrets/general.yaml;
        owner = "openclaw";
        group = "openclaw";
        mode = "0400";
        restartUnits = [ "openclaw-gateway.service" ];
      };

      services.openclaw-gateway = {
        enable = true;
        # These are upstream defaults, repeated to make the trust boundary
        # obvious where the host opts into this bucket.
        user = "openclaw";
        group = "openclaw";
        createUser = true;
        stateDir = "/var/lib/openclaw";
        # Keep the service runtime minimal; the batteries-included CLI remains
        # available separately in environment.systemPackages below.
        package = pkgs.openclaw-gateway;

        config = {
          agents.defaults.model.primary = "github-copilot/gpt-5.6-sol";

          secrets.providers.gateway_token_file = {
            source = "file";
            path = config.sops.secrets.openclaw-gateway-token.path;
            mode = "singleValue";
          };

          # Windows reaches WSL services through localhost forwarding. Advertise
          # that stable same-machine address for Companion setup codes without
          # exposing the Gateway on the LAN.
          plugins.entries."device-pair" = {
            enabled = true;
            config.publicUrl = "ws://127.0.0.1:18789";
          };

          gateway = {
            mode = "local";
            bind = "loopback";
            auth = {
              mode = "token";
              token = {
                source = "file";
                provider = "gateway_token_file";
                id = "value";
              };
            };
          };
        };
      };

      # The upstream NixOS module creates the user and service but intentionally
      # leaves systemd hardening to the host. Only the state directory is
      # writable; /home (including Miles's credentials) is inaccessible.
      systemd.services.openclaw-gateway.serviceConfig = {
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        ProtectSystem = "strict";
        ProtectHome = true;
        # ProtectHome does not cover WSL automounts, whose Windows user trees
        # are otherwise traversable by this UID.
        InaccessiblePaths = [ "-/mnt" ];
        ReadWritePaths = [ config.services.openclaw-gateway.stateDir ];
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectProc = "invisible";
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        LockPersonality = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
        UMask = "0077";
        # Node/V8 JIT compilation needs executable writable memory.
        MemoryDenyWriteExecute = false;
      };

      # Keep the raw CLI for documentation/completions, plus safe entry points
      # that target the system gateway's identity and state explicitly.
      environment.systemPackages = [
        pkgs.openclaw
        openclawAdmin
        openclawTui
      ];
    };
}
