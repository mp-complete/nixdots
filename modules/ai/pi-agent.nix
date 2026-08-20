# pi-agent: a Nix-configurable daemon that runs pi on a schedule.
#
# A *job* is a prompt + (optionally) a repo + a schedule + a toolset, run
# unattended by a headless pi as a dedicated system user. See
# docs/proposals/pi-agent-daemon.md for the full rationale.
#
# Opt in with `buckets = [ … "pi-agent" ]`, then declare jobs from any file:
#
#   flake.modules.nixos.pi-agent = { pkgs, ... }: {
#     piAgent.jobs.my-job = { schedule = "daily"; prompt = "…"; };
#   };
#
# One interactive bootstrap per host is required before the first run:
# `pi-agent-login` (the daemon holds its OWN OAuth grant — see the Auth note
# on `piAgent.package` below).
{ config, ... }:
let
  outer = config;
in
{
  flake.modules.nixos.pi-agent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.piAgent;

      # StateDirectory= is relative to /var/lib, so the state dir has to live
      # there (asserted below).
      stateDirName = lib.removePrefix "/var/lib/" cfg.stateDir;

      # Options shared by `piAgent.defaults` and each job. Everything here is
      # nullable / empty-by-default so `mergeDefaults` can tell "unset" from
      # "set to something" without module-system priority games.
      commonOptions = {
        model = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "sonnet";
          description = "`--model` pattern for the run.";
        };
        thinking = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "off"
              "minimal"
              "low"
              "medium"
              "high"
              "xhigh"
              "max"
            ]
          );
          default = null;
          description = "`--thinking` level.";
        };
        tools = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [
            "read"
            "grep"
            "bash"
          ];
          description = ''
            `--tools` allowlist. Empty means "every tool pi loaded".
            Concatenated with `piAgent.defaults.tools`.
          '';
        };
        excludeTools = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "`--exclude-tools` denylist, concatenated with the defaults.";
        };
        extraExtensions = lib.mkOption {
          type = lib.types.listOf lib.types.path;
          default = [ ];
          description = "Extra `--extension` paths on top of the pi-daemon wrapper's set.";
        };
        skills = lib.mkOption {
          type = lib.types.listOf lib.types.path;
          default = [ ];
          description = "Extra `--skill` paths.";
        };
        appendSystemPrompt = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = ''
            Rendered to a store file and passed via `--append-system-prompt`.
            The defaults' text is prepended to the job's.
          '';
        };
        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          example = lib.literalExpression "with pkgs; [ git gh nix ]";
          description = "Packages placed on the job's PATH (git, gh, az, nodejs, …).";
        };
        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Extra unit `Environment=` entries. Never put secrets here — the unit env is world-readable.";
        };
        environmentFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = lib.literalExpression ''config.sops.templates."pi-agent-gh.env".path'';
          description = "`EnvironmentFile=` — e.g. a sops template holding a forge token.";
        };
        credentials = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          default = { };
          example = lib.literalExpression "{ ado-pat = config.sops.secrets.ado-pat.path; }";
          description = ''
            `LoadCredential=` entries, readable at `$CREDENTIALS_DIRECTORY/<name>`.
            Preferred over `environmentFile`: never lands in the unit environment.
          '';
        };
        timeout = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "`TimeoutStartSec=` — the hang backstop. Defaults to 45m.";
        };
        randomizedDelay = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Timer jitter (`RandomizedDelaySec=`). Defaults to 10m.";
        };
        persistent = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Catch up runs missed while the machine was off. Defaults to true.";
        };
        approveProject = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = ''
            Pass `--approve`, i.e. trust the checkout's `.pi/` and
            `.agents/skills`. Defaults to false — only turn this on for repos
            you own, it is a prompt-injection surface.
          '';
        };
        keepRuns = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          description = "How many run transcripts to keep per job. Defaults to 30.";
        };
        preRun = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Shell run before pi. `$WORKDIR`, `$JOB_DIR`, `$RUN_ID`, `$RUN_LOG` are in scope.";
        };
        postRun = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Shell run after pi, before the exit-code verdict. Same variables plus `$rc`.";
        };
        serviceConfig = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Escape hatch merged last into the unit's `serviceConfig`.";
        };
      };

      jobModule =
        { name, ... }:
        {
          options = commonOptions // {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Jobs are data, so a real toggle is fine here (unlike bucket gates).";
            };
            description = lib.mkOption {
              type = lib.types.str;
              default = "pi-agent job ${name}";
              description = "Unit `Description=`.";
            };
            schedule = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "*-*-* 02:30:00";
              description = ''
                systemd `OnCalendar=` expression. `null` generates the service
                but no timer — a manual-only job (`pi-agent-run <name>`).
              '';
            };
            prompt = lib.mkOption {
              type = lib.types.lines;
              default = "";
              description = "The task. Rendered to a store file and passed as pi's initial message.";
            };
            promptFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Use this file as the prompt instead of `prompt`.";
            };
            repo = lib.mkOption {
              default = null;
              description = "Repository the job works on. `null` = repo-less job (empty workspace).";
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    url = lib.mkOption { type = lib.types.str; };
                    ref = lib.mkOption {
                      type = lib.types.str;
                      default = "main";
                    };
                    depth = lib.mkOption {
                      type = lib.types.nullOr lib.types.ints.positive;
                      default = null;
                      description = "Shallow-clone depth. Leave null when the agent needs history.";
                    };
                    subdir = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Run pi in this subdirectory of the checkout.";
                    };
                  };
                }
              );
            };
          };
        };

      d = cfg.defaults;
      pick =
        a: b: fallback:
        if a != null then
          a
        else if b != null then
          b
        else
          fallback;

      # Explicit, boring merge of `piAgent.defaults` into a job: scalars fall
      # back, lists concatenate, attrsets are overlaid job-last.
      mergeDefaults =
        job:
        job
        // {
          model = pick job.model d.model null;
          thinking = pick job.thinking d.thinking null;
          timeout = pick job.timeout d.timeout "45m";
          randomizedDelay = pick job.randomizedDelay d.randomizedDelay "10m";
          persistent = pick job.persistent d.persistent true;
          approveProject = pick job.approveProject d.approveProject false;
          keepRuns = pick job.keepRuns d.keepRuns 30;
          environmentFile = pick job.environmentFile d.environmentFile null;
          tools = d.tools ++ job.tools;
          excludeTools = d.excludeTools ++ job.excludeTools;
          extraExtensions = d.extraExtensions ++ job.extraExtensions;
          skills = d.skills ++ job.skills;
          packages = d.packages ++ job.packages;
          appendSystemPrompt = lib.concatStringsSep "\n" (
            lib.filter (s: s != "") [
              d.appendSystemPrompt
              job.appendSystemPrompt
            ]
          );
          environment = d.environment // job.environment;
          credentials = d.credentials // job.credentials;
          serviceConfig = d.serviceConfig // job.serviceConfig;
          preRun = lib.concatStringsSep "\n" (
            lib.filter (s: s != "") [
              d.preRun
              job.preRun
            ]
          );
          postRun = lib.concatStringsSep "\n" (
            lib.filter (s: s != "") [
              job.postRun
              d.postRun
            ]
          );
        };

      jobs = lib.mapAttrs (_: mergeDefaults) cfg.jobs;
      enabledJobs = lib.filterAttrs (_: j: j.enable) jobs;

      runnerFor =
        name: job:
        import ./pi-agent/_runner.nix {
          inherit
            pkgs
            lib
            name
            job
            ;
          inherit (cfg) stateDir;
          piPackage = cfg.package;
        };

      runners = lib.mapAttrs runnerFor jobs;

      # Helpers, on the host's PATH.
      loginScript = pkgs.writeShellApplication {
        name = "pi-agent-login";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          # One interactive OAuth bootstrap per host. The daemon must hold its
          # OWN grant: sharing your ~/.pi auth.json means provider refresh-token
          # rotation logs one of you out at random.
          echo "Starting an interactive pi as ${cfg.user} in ${cfg.stateDir}/agent."
          echo "Run /login, complete the flow, then /exit."
          exec sudo -u ${cfg.user} --set-home \
            env PI_CODING_AGENT_DIR=${cfg.stateDir}/agent HOME=${cfg.stateDir} \
            ${lib.getExe cfg.package}
        '';
      };

      importAuthScript = pkgs.writeShellApplication {
        name = "pi-agent-import-auth";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          # FALLBACK ONLY. Copying your personal auth.json in means you and the
          # daemon share one credential: when the provider rotates the refresh
          # token, whichever side refreshes second gets logged out. Prefer
          # pi-agent-login.
          src="''${1:-$HOME/.pi/agent/auth.json}"
          [ -f "$src" ] || { echo "no auth.json at $src" >&2; exit 1; }
          echo "WARNING: sharing one OAuth grant between you and the daemon can log you out at random." >&2
          sudo install -o ${cfg.user} -g ${cfg.group} -m 0600 \
            "$src" ${cfg.stateDir}/agent/auth.json
        '';
      };

      runScript = pkgs.writeShellApplication {
        name = "pi-agent-run";
        text = ''
          job="''${1:?usage: pi-agent-run <job>}"
          sudo systemctl start --no-block "pi-agent-$job.service"
          exec journalctl -fu "pi-agent-$job.service"
        '';
      };

      statusScript = pkgs.writeShellApplication {
        name = "pi-agent-status";
        text = ''
          systemctl list-timers 'pi-agent-*' --all
          echo
          systemctl list-units 'pi-agent-*' --all --no-pager
        '';
      };
    in
    {
      options.piAgent = {
        package = lib.mkOption {
          type = lib.types.package;
          default = outer.flake.wrappers.pi-daemon.wrap { inherit pkgs; };
          defaultText = lib.literalExpression "flake.wrappers.pi-daemon";
          description = ''
            The pi used by every job. Defaults to the headless `pi-daemon`
            wrapper, which excludes every extension that can block on human
            input.
          '';
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "pi-agent";
          description = "System user the jobs run as.";
        };
        group = lib.mkOption {
          type = lib.types.str;
          default = "pi-agent";
          description = "Group the jobs run as.";
        };
        stateDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/pi-agent";
          description = ''
            Home of the daemon: `agent/` (pi config + auth.json) and
            `jobs/<name>/{work,runs,sessions}`. Must live under /var/lib
            because the units use `StateDirectory=`.
          '';
        };

        defaults = lib.mkOption {
          type = lib.types.submodule { options = commonOptions; };
          default = { };
          description = "Merged into every job — set `model`, `packages`, `timeout` once.";
        };

        jobs = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule jobModule);
          default = { };
          description = "The jobs. Each generates a `pi-agent-<name>.service` (+ timer when scheduled).";
        };

        runners = lib.mkOption {
          type = lib.types.attrsOf lib.types.package;
          readOnly = true;
          internal = true;
          default = runners;
          description = ''
            Per-job runner scripts. Runnable outside systemd for testing:
            `PI_AGENT_STATE_DIR=$PWD/state ./pi-agent-<name>`.
          '';
        };
      };

      config = {
        assertions = [
          {
            assertion = lib.hasPrefix "/var/lib/" cfg.stateDir;
            message = "piAgent.stateDir must live under /var/lib (StateDirectory= is relative to it).";
          }
        ]
        ++ lib.mapAttrsToList (n: job: {
          assertion = job.prompt != "" || job.promptFile != null;
          message = "piAgent.jobs.${n}: set either `prompt` or `promptFile`.";
        }) enabledJobs
        ++ lib.mapAttrsToList (n: job: {
          # pi's arg parser has no `--` separator, so a leading dash would be
          # eaten as a flag.
          assertion = !(lib.hasPrefix "-" job.prompt);
          message = "piAgent.jobs.${n}: prompt must not start with '-' (pi parses it as a flag).";
        }) enabledJobs;

        users.users.${cfg.user} = {
          isSystemUser = true;
          inherit (cfg) group;
          # ProtectHome=true hides /home, so the daemon's home MUST be the
          # state dir or nothing (git, node, pi) has a writable home.
          home = cfg.stateDir;
          createHome = false;
          description = "pi-agent unattended coding agent";
        };
        users.groups.${cfg.group} = { };

        # Created up-front so `pi-agent-login` works before any unit has run
        # (StateDirectory= only materializes on first start).
        systemd.tmpfiles.settings."10-pi-agent" = {
          ${cfg.stateDir}.d = {
            inherit (cfg) user group;
            mode = "0700";
          };
          "${cfg.stateDir}/agent".d = {
            inherit (cfg) user group;
            mode = "0700";
          };
          "${cfg.stateDir}/jobs".d = {
            inherit (cfg) user group;
            mode = "0700";
          };
        };

        systemd.slices.pi-agent = {
          description = "pi-agent unattended coding agent jobs";
          sliceConfig = {
            # One knob to throttle every job at once if a run goes feral.
            CPUWeight = 50;
            IOWeight = 50;
          };
        };

        systemd.services = lib.mapAttrs' (
          name: job:
          lib.nameValuePair "pi-agent-${name}" {
            inherit (job) description;
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            path = job.packages;

            environment = {
              PI_CODING_AGENT_DIR = "${cfg.stateDir}/agent";
              PI_AGENT_STATE_DIR = cfg.stateDir;
              HOME = cfg.stateDir;
              XDG_CACHE_HOME = "${cfg.stateDir}/cache";
              SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
              GIT_TERMINAL_PROMPT = "0";
            }
            // job.environment;

            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe runners.${name};
              User = cfg.user;
              Group = cfg.group;

              StateDirectory = [
                stateDirName
                "${stateDirName}/agent"
                "${stateDirName}/cache"
                "${stateDirName}/jobs/${name}/work"
                "${stateDirName}/jobs/${name}/runs"
                "${stateDirName}/jobs/${name}/sessions"
              ];
              StateDirectoryMode = "0700";
              WorkingDirectory = "${cfg.stateDir}/jobs/${name}/work";
              Slice = "pi-agent.slice";
              TimeoutStartSec = job.timeout;

              EnvironmentFile = lib.optional (job.environmentFile != null) job.environmentFile;
              LoadCredential = lib.mapAttrsToList (n: p: "${n}:${p}") job.credentials;

              # --- sandbox ---------------------------------------------------
              NoNewPrivileges = true;
              CapabilityBoundingSet = "";
              ProtectSystem = "strict"; # StateDirectory is auto-added to ReadWritePaths
              ProtectHome = true; # => the daemon's home must be stateDir
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
              # AF_UNIX is required for the nix daemon socket.
              RestrictAddressFamilies = [
                "AF_INET"
                "AF_INET6"
                "AF_UNIX"
              ];
              LockPersonality = true;
              SystemCallArchitectures = "native";
              SystemCallFilter = [ "@system-service" ];
              UMask = "0077";
              # MUST stay false: V8/Node needs W+X pages for the JIT.
              MemoryDenyWriteExecute = false;
              # DynamicUser is unusable here — auth.json must persist across
              # runs with stable ownership.
            }
            // job.serviceConfig;
          }
        ) enabledJobs;

        systemd.timers = lib.mapAttrs' (
          name: job:
          lib.nameValuePair "pi-agent-${name}" {
            inherit (job) description;
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = job.schedule;
              Persistent = job.persistent;
              RandomizedDelaySec = job.randomizedDelay;
              AccuracySec = "1m";
              Unit = "pi-agent-${name}.service";
            };
          }
        ) (lib.filterAttrs (_: j: j.schedule != null) enabledJobs);

        environment.systemPackages = [
          loginScript
          importAuthScript
          runScript
          statusScript
        ];
      };
    };
}
