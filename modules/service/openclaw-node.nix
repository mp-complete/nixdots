{ inputs, ... }:
{
  # Opt-in node role. Runs a headless OpenClaw node host that connects to a
  # gateway and lets it route tool calls here when `host=node` is selected.
  # Connects to a gateway at `127.0.0.1:18789` over loopback by default (e.g. a
  # work gateway reached through WSL localhost forwarding); point
  # `services.openclaw-node.gateway*` elsewhere for a different one.
  #
  # The node runs as its own system user in a dedicated state dir, with /home
  # (Miles's credentials) and the Windows automounts inaccessible. Loosen
  # `serviceConfig` below only if you deliberately want the node to act on
  # Miles's environment.
  flake.modules.nixos.openclaw-node =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.services.openclaw-node;

      # Token auth. The gateway runs in token-auth mode, so every node
      # connection must present the shared gateway token via
      # OPENCLAW_GATEWAY_TOKEN (`node run` has no token flag -- env only). The
      # wrapper reads the SOPS-provisioned token file and exports it, so the
      # secret never lands in the unit file or the Nix store.
      #
      # Authenticating is separate from approval: on first connect the node
      # registers its capability surface as *pending*, and an operator approves
      # it once on the gateway with `openclaw nodes approve <id>` (see
      # `openclaw nodes pending`). After that the node reconnects and works with
      # no further interaction.
      nodeRun = pkgs.writeShellApplication {
        name = "openclaw-node-run";
        runtimeInputs = [
          pkgs.openclaw
          pkgs.coreutils
        ];
        text = ''
          token_file=${lib.escapeShellArg cfg.gatewayTokenFile}
          if [[ ! -s "$token_file" ]]; then
            echo "openclaw-node: gateway token file $token_file is missing or empty; set the gateway token in SOPS (secrets/general.yaml: work-openclaw-gateway-token)" >&2
            exit 1
          fi
          OPENCLAW_GATEWAY_TOKEN="$(tr -d '[:space:]' < "$token_file")"
          export OPENCLAW_GATEWAY_TOKEN

          args=(
            node run
            --host ${lib.escapeShellArg cfg.gatewayHost}
            --port ${toString cfg.gatewayPort}
          )
          ${lib.optionalString cfg.gatewayTls "args+=(--tls)"}
          ${lib.optionalString (!cfg.gatewayTls) "args+=(--no-tls)"}
          ${lib.optionalString (
            cfg.contextPath != null
          ) "args+=(--context-path ${lib.escapeShellArg cfg.contextPath})"}
          ${lib.optionalString (
            cfg.displayName != null
          ) "args+=(--display-name ${lib.escapeShellArg cfg.displayName})"}
          ${lib.optionalString (
            cfg.tlsFingerprint != null
          ) "args+=(--tls-fingerprint ${lib.escapeShellArg cfg.tlsFingerprint})"}

          exec openclaw "''${args[@]}"
        '';
      };

      # Gateway-scoped admin CLI, run as the node user against its state. Use
      # this for `openclaw node status`, `openclaw node identity`, etc.
      nodeAdmin = pkgs.writeShellApplication {
        name = "openclaw-node-admin";
        text = ''
          env_args=(
            "HOME=${cfg.stateDir}"
            "OPENCLAW_STATE_DIR=${cfg.stateDir}"
            "OPENCLAW_NIX_MODE=1"
            "TERM=''${TERM:-xterm-256color}"
          )
          [[ -n "''${COLORTERM:-}" ]] && env_args+=("COLORTERM=$COLORTERM")

          exec ${config.security.wrapperDir}/sudo -u ${cfg.user} --set-home \
            ${pkgs.coreutils}/bin/env "''${env_args[@]}" \
            ${pkgs.openclaw}/bin/openclaw "$@"
        '';
      };
    in
    {
      options.services.openclaw-node = with lib; {
        gatewayHost = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "OpenClaw gateway host this node connects to. Defaults to the local system gateway over loopback.";
        };
        gatewayPort = mkOption {
          type = types.port;
          default = 18789;
          description = "Gateway port. 18789 is the local gateway's loopback WebSocket port.";
        };
        gatewayTls = mkOption {
          type = types.bool;
          default = false;
          description = "Use TLS (wss://) for the gateway connection. False for a loopback (ws://) gateway.";
        };
        contextPath = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "/openclaw-gw";
          description = "Gateway WebSocket context path, if the gateway is served under a sub-path.";
        };
        tlsFingerprint = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Expected gateway TLS certificate fingerprint (sha256), for pinning.";
        };
        displayName = mkOption {
          type = types.nullOr types.str;
          default = config.networking.hostName;
          defaultText = literalExpression "config.networking.hostName";
          description = "Node display name shown on the gateway.";
        };
        user = mkOption {
          type = types.str;
          default = "openclaw-node";
          description = "System user running the node host.";
        };
        group = mkOption {
          type = types.str;
          default = "openclaw-node";
          description = "System group running the node host.";
        };
        stateDir = mkOption {
          type = types.path;
          default = "/var/lib/openclaw-node";
          description = "Node host state directory (device identity, saved gateway binding, sessions).";
        };
        gatewayTokenFile = mkOption {
          type = types.path;
          default = config.sops.secrets.openclaw-node-gateway-token.path;
          defaultText = literalExpression "config.sops.secrets.openclaw-node-gateway-token.path";
          description = ''
            Path to a file containing the shared gateway auth token (the gateway
            runs in token auth mode). Read into OPENCLAW_GATEWAY_TOKEN at service
            start. Defaults to a node-owned secret that reads the
            `work-openclaw-gateway-token` YAML value. This is a stable secret --
            unlike short-lived join codes -- so it belongs in SOPS.
          '';
        };
      };

      config = {
        nixpkgs.overlays = [ inputs.nix-openclaw.overlays.default ];

        # The node authenticates with the gateway's shared token, stored in SOPS
        # as `work-openclaw-gateway-token` and read into a node-owned secret
        # file.
        sops.secrets.openclaw-node-gateway-token = {
          sopsFile = ../../secrets/general.yaml;
          key = "work-openclaw-gateway-token";
          owner = cfg.user;
          group = cfg.group;
          mode = "0400";
          restartUnits = [ "openclaw-node.service" ];
        };

        users.groups.${cfg.group} = { };
        users.users.${cfg.user} = {
          isSystemUser = true;
          group = cfg.group;
          home = cfg.stateDir;
          createHome = true;
          shell = pkgs.bashInteractive;
        };

        systemd.tmpfiles.rules = [
          "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} - -"
        ];

        systemd.services.openclaw-node = {
          description = "OpenClaw node host (connects to remote gateway)";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          environment = {
            HOME = cfg.stateDir;
            OPENCLAW_STATE_DIR = cfg.stateDir;
            OPENCLAW_NIX_MODE = "1";
          };

          serviceConfig = {
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = cfg.stateDir;
            ExecStart = "${nodeRun}/bin/openclaw-node-run";
            Restart = "on-failure";
            RestartSec = 5;

            # Hardening mirrors the gateway bucket: only the node's own state is
            # writable; /home and the WSL Windows automounts stay inaccessible.
            NoNewPrivileges = true;
            CapabilityBoundingSet = "";
            ProtectSystem = "strict";
            ProtectHome = true;
            InaccessiblePaths = [ "-/mnt" ];
            ReadWritePaths = [ cfg.stateDir ];
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

          path = [
            pkgs.bash
            pkgs.coreutils
          ];
        };

        environment.systemPackages = [
          pkgs.openclaw
          nodeAdmin
        ];
      };
    };
}
