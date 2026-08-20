# Proposal: `pi-agent` — a Nix-configurable daemon that runs pi on a schedule

Status: **phase 1 implemented, not deployed anywhere.** The module evaluates,
builds, and has been exercised by hand end-to-end (clone → prompt → pi →
transcript). No host imports the bucket yet.

What landed:

| File | What |
| --- | --- |
| `modules/ai/pi.nix` | `flake.wrappers.pi-daemon` — headless extension set |
| `modules/ai/pi-agent.nix` | `flake.modules.nixos.pi-agent` — options + user/slice/tmpfiles + unit generation + helper scripts |
| `modules/ai/pi-agent/_runner.nix` | the per-job runner-script builder |
| `modules/ai/jobs/docs-pr.nix` | the worked example job (`enable = false`) + `piAgent.defaults` prompt hygiene |
| `modules/ai/pi-agent-check.nix` | `checks.<sys>.pi-agent-eval` + `packages.<sys>.pi-agent-runner-<n>` |

Deviations from the plan below, all forced by reality:

- **No VM test.** Tiers 1 and 2 landed; tier 3 was judged too heavy for now and
  is deferred with the rest of phase 2.
- **The prompt is passed as a positional message, not `@file`.** pi's arg parser
  has no `--` separator and treats `@file` as *attached context* rather than the
  task, so the runner does `pi … "$(cat <store-path>)"` and the module asserts
  the prompt does not start with `-`.
- **`git checkout -f -B`**, not `checkout -B`: a run that died mid-edit leaves a
  dirty tree, and a plain checkout refuses to switch. Found by testing.
- `piAgent.defaults` is merged into jobs by an explicit function (scalars fall
  back, lists concatenate, attrsets overlay) rather than by module-system
  priority games, so a default can never silently conflict with a job.

## Goal

Declaratively define *jobs* — a prompt + a repo + a schedule + a toolset — that a
headless pi runs unattended. Motivating example:

> Every night, pull `main` of repo X, look for documentation that has drifted from
> the code, and either open a PR with the fixes or file work items under a story.

## Decisions (settled)

| Axis | Decision |
| --- | --- |
| Target host | none for now; **hilbert** eventually. Module is written host-agnostic and opted into via a `pi-agent` bucket. |
| Isolation | **Hardened systemd oneshot unit running as a dedicated `pi-agent` system user.** No container runtime. |
| Model auth | **Reuse subscription OAuth** (`auth.json`), but the daemon gets its *own* grant rather than sharing yours — see [Auth](#auth-the-one-genuinely-tricky-part). |
| Triggers | **systemd timers only** in phase 1. Manual `systemctl start` falls out for free. Webhooks/path-units deferred. |

## Why this shape

pi already has everything needed to be a daemon; nothing needs patching:

- `pi -p` / `pi --mode json` are fully non-interactive and **never prompt for tool
  approval** — pi has no permission system (see pi `docs/security.md`). So a
  scheduled run just works, and the isolation burden is entirely ours.
- `--mode json` emits an event stream (`agent_start`, `tool_execution_*`,
  `agent_end`, …) — a machine-readable audit log per run, perfect for journald
  summaries + archived JSONL.
- `PI_CODING_AGENT_DIR` relocates the whole config/auth/session dir, which is what
  lets a `pi-agent` system user exist at all without a real home.
- `--tools` / `--exclude-tools` / `--no-builtin-tools` give a per-job capability
  allowlist at the pi layer, on top of the systemd sandbox.
- Non-interactive modes never show a project-trust prompt, so a repo's `.pi/` or
  `.agents/skills` is ignored unless the job passes `--approve`. That's a useful
  per-job knob: **don't** approve for third-party repos.

## Component map

```
modules/ai/pi.nix               (edit)  + flake.wrappers.pi-daemon — headless extension set
modules/ai/pi-agent.nix         (new)   flake.modules.nixos.pi-agent — options + systemd generation
modules/ai/pi-agent/_runner.nix (new)   the runner-script builder (leading _ keeps it out of import-tree)
modules/ai/jobs/docs-pr.nix     (new)   one worked example job, merged into the same bucket
modules/ai/pi-agent-check.nix   (new)   flake.checks.<sys>.pi-agent-eval — cheap eval/build check
```

Everything stays dendritic: each file sets `flake.modules.nixos.pi-agent` (or
`flake.wrappers.*` / `flake.checks.*`) and merges. A host opts in with
`buckets = [ … "pi-agent" ];`. No host is changed in phase 1.

---

## 1. A third pi wrapper: `pi-daemon`

`modules/ai/pi.nix` already has `mkPi extNames` producing `pi-desktop` / `pi-wsl`.
Add a third list. The critical rule: **every extension that can block on human
input must be excluded**, or a nightly job silently hangs until the systemd
timeout.

```nix
# in modules/ai/pi.nix
daemonExtensions = [
  "pi-hermes-memory"     # cross-run memory + session search; agent dir is isolated
  "pi-web-access"        # fetch docs/URLs — most doc jobs want this
  "pi-copilot-discovery" # model discovery
  "notify"               # push job outcomes to Gotify/ntfy
];
# deliberately NOT included: pi-catppuccin, rpiv-todo, rpiv-btw,
# rpiv-ask-user-question, edb-agent-steer, pi-interview  (all TUI/interactive)

flake.wrappers.pi-daemon = mkPi daemonExtensions;
```

Free wins: `nix build .#pi-daemon` works immediately, and `nix flake check` builds
it via the existing `checks.nix` wiring once a host imports it (or via the VM test
below before then).

Belt-and-braces at the job layer: default `excludeTools = [ "ask_question" "ask_user_question" "interview" ]`.

---

## 2. Option schema

Declared inside the nixos bucket so jobs can use host `pkgs`/`lib`:

```nix
piAgent = {
  package        = mkPackageOption;          # default: the pi-daemon wrapper
  user / group   = "pi-agent";
  stateDir       = "/var/lib/pi-agent";
  defaults       = <same submodule as a job, minus schedule/prompt>;  # merged into every job
  jobs.<name>    = { … };
};
```

Per-job submodule:

| Option | Type | Notes |
| --- | --- | --- |
| `enable` | bool = true | jobs are *data*, so a real toggle is fine here (unlike bucket gates) |
| `description` | str | unit `Description=` |
| `schedule` | nullOr str | systemd `OnCalendar`, e.g. `"*-*-* 02:30:00"` or `"daily"`. `null` = service but no timer (manual-only job) |
| `randomizedDelay` | str = `"10m"` | jitter so nightly jobs don't stampede |
| `persistent` | bool = true | catch up runs missed while the box was off |
| `prompt` / `promptFile` | lines / path | the task. `promptFile` wins; both render to a store file, read into pi's initial message |
| `repo` | null or `{ url; ref = "main"; depth = null; subdir = null; }` | null = repo-less job |
| `model` / `thinking` | nullOr str | `--model` / `--thinking` |
| `tools` / `excludeTools` | listOf str | `--tools` allowlist / `--exclude-tools` |
| `extraExtensions` / `skills` | listOf path | extra `-e` / `--skill` |
| `appendSystemPrompt` | lines | rendered to a file, passed via `--append-system-prompt` |
| `approveProject` | bool = false | pass `--approve` (only for repos you own) |
| `packages` | listOf package | prepended to the job `PATH` (`git`, `gh`, `az`, `nodejs`, …) |
| `environment` | attrsOf str | unit `Environment=` |
| `environmentFile` | nullOr path | sops template path → `EnvironmentFile=` (GH/ADO tokens) |
| `credentials` | attrsOf path | `LoadCredential=`, exposed at `$CREDENTIALS_DIRECTORY` |
| `timeout` | str = `"45m"` | `TimeoutStartSec=` — the hang backstop |
| `keepRuns` | int = 30 | how many run transcripts to keep per job |
| `preRun` / `postRun` | lines | shell hooks around the pi call (`$WORKDIR`, `$RUN_LOG` in scope) |
| `serviceConfig` | attrsOf anything | escape hatch, merged last |

`piAgent.defaults` exists so `model`, `packages`, `environmentFile`, `timeout` are
set once rather than per job.

---

## 3. Generated units

For each enabled job `<n>`, exactly two units (plain units, **not** a `@` template
— template units can't carry per-instance Nix config):

```nix
systemd.services."pi-agent-${n}" = {
  description = job.description;
  after = [ "network-online.target" ];
  wants = [ "network-online.target" ];
  path  = job.packages;
  serviceConfig = {
    Type              = "oneshot";
    ExecStart         = "${runnerFor n job}/bin/pi-agent-${n}";
    User = "pi-agent"; Group = "pi-agent";
    StateDirectory    = "pi-agent pi-agent/jobs/${n}";
    StateDirectoryMode= "0700";
    WorkingDirectory  = "%S/pi-agent/jobs/${n}/work";
    Slice             = "pi-agent.slice";
    TimeoutStartSec   = job.timeout;
    …hardening…
  };
};

systemd.timers."pi-agent-${n}" = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar        = job.schedule;
    Persistent        = job.persistent;
    RandomizedDelaySec= job.randomizedDelay;
    AccuracySec       = "1m";
  };
};
```

### Hardening block (with the gotchas that actually bite)

```
NoNewPrivileges       = true
CapabilityBoundingSet = ""
ProtectSystem         = "strict"      # StateDirectory is auto-added to ReadWritePaths
ProtectHome           = true          # -> pi-agent's home MUST be /var/lib/pi-agent
PrivateTmp            = true
PrivateDevices        = true
ProtectProc           = "invisible"
ProtectClock/Hostname/KernelTunables/KernelModules/KernelLogs/ControlGroups = true
RestrictNamespaces    = true
RestrictRealtime      = true
RestrictSUIDSGID      = true
RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ]   # AF_UNIX needed for the nix daemon socket
LockPersonality       = true
SystemCallArchitectures = "native"
SystemCallFilter      = [ "@system-service" ]
UMask                 = "0077"
MemoryDenyWriteExecute = false        # ⚠ MUST stay false — V8/Node JIT needs W+X
```

Two more traps worth writing into comments:

- **`ProtectHome=true` means `/home` is invisible.** Any job that wants to touch a
  checkout under `~` won't. That is the point — work happens in the StateDirectory.
- **`DynamicUser` is not usable here** because the OAuth `auth.json` must persist
  across runs with stable ownership.

---

## 4. The runner script

`pkgs.writeShellApplication`, one per job, also exposed as
`packages.<system>.pi-agent-runner-<n>` so it can be executed **by hand, outside
systemd**, which is the main phase-1 test path.

```sh
set -euo pipefail
AGENT_DIR="${PI_CODING_AGENT_DIR:-$STATE_DIRECTORY/agent}"
WORKDIR=…/jobs/<n>/work
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
RUN_LOG=…/jobs/<n>/runs/$RUN_ID.jsonl

# 1. serialize: one pi at a time, so concurrent jobs never race on auth.json
#    refresh or the hermes-memory sqlite lock.
exec 9>"$AGENT_DIR/.pi-agent.lock"; flock 9

# 2. deterministic workspace (only when job.repo != null)
if [ -d "$WORKDIR/.git" ]; then
  git -C "$WORKDIR" fetch --prune origin
else
  git clone --branch "$REF" "$URL" "$WORKDIR"
fi
git -C "$WORKDIR" checkout -B "$REF" "origin/$REF"
git -C "$WORKDIR" reset --hard "origin/$REF"
git -C "$WORKDIR" clean -fdx        # every run starts from a clean tree

# 3. preRun hook

# 4. the actual agent
cd "$WORKDIR"
pi --mode json \
   --session-dir "…/jobs/<n>/sessions" \
   --name "<n> $RUN_ID" \
   [--model …] [--thinking …] [--tools …] [--exclude-tools …] \
   [-e …] [--skill …] [--append-system-prompt <file>] [--approve] \
   "@$PROMPT_FILE" \
  | tee "$RUN_LOG" \
  | <summarizer>          # jq/node: print text deltas + tool names to journald

# 5. postRun hook; exit non-zero if the stream contained an error / no agent_end
```

Design notes:

- `--mode json` rather than `-p`: same non-interactive behaviour, but you get a
  full structured transcript per run for postmortems, plus a reliable way to detect
  failure (missing `agent_end`, `tool_execution_end` with `isError`).
- Sessions are kept per job (`--session-dir`) — `pi --session <id>` can replay a
  bad night's run interactively.
- `flock` on a shared agent dir is deliberately simple; the alternative
  (per-job agent dirs) multiplies the OAuth bootstrap by the number of jobs.
- **The agent does the git/PR work itself**, via `gh`/`glab`/`az` on `PATH` and a
  skill in the prompt — not via bash plumbing in the runner. That keeps the runner
  generic and the job definition declarative.

---

## 5. Auth: the one genuinely tricky part

`auth.json` holds OAuth tokens and pi **auto-refreshes and rewrites it**. Two
consequences:

1. It cannot be a read-only bind of your personal `~/.pi/agent/auth.json` — refresh
   would fail.
2. If daemon and interactive session share one credential and the provider rotates
   refresh tokens, **one of them gets logged out at random**. This is the failure
   mode to avoid.

**Recommended: give the daemon its own grant.** Ship a helper in the bucket's
`environment.systemPackages`:

```sh
pi-agent-login          # sudo -u pi-agent -H \
                        #   env PI_CODING_AGENT_DIR=/var/lib/pi-agent/agent \
                        #   <pi-daemon>/bin/pi   → then /login
```

One interactive bootstrap per host, then the daemon refreshes its own token
forever, fully independent of your session. Also ship:

```sh
pi-agent-run <name>     # systemctl start pi-agent-<name>.service && journalctl -fu …
pi-agent-status         # systemctl list-timers 'pi-agent-*'
```

**Fallback** (`pi-agent-import-auth`, copying your `auth.json` in): document it,
but flag the rotation hazard loudly in a comment. Worth adding an
`piAgent.authFile` option later for an API key via sops, as an escape hatch when
OAuth rotation gets annoying.

Git/forge credentials are **separate** from model auth: a `gh`/ADO token from
`secrets/`, delivered per job via `environmentFile` (sops template) or
`credentials` (`LoadCredential`, better — never lands in the unit env).

---

## 6. Worked example — the nightly docs PR

```nix
# modules/ai/jobs/docs-pr.nix
{
  flake.modules.nixos.pi-agent.piAgent.jobs.nixdots-docs = {
    description = "Nightly documentation drift check on nixdots";
    schedule    = "*-*-* 02:30:00";
    repo = { url = "https://github.com/…/nixdots.git"; ref = "main"; };
    packages    = p: [ p.git p.gh p.nix ];
    approveProject = true;                 # own repo: load its .agents/skills
    environmentFile = config.sops.templates."pi-agent-gh.env".path;
    tools = [ "read" "grep" "find" "ls" "edit" "write" "bash" ];
    prompt = ''
      You are running unattended on a fresh clone of main.

      1. Compare docs/ and every AGENTS.md / README against the current code.
      2. If nothing has drifted, print "NO CHANGES" and stop. Do not open a PR.
      3. Otherwise: create branch `bot/docs-<date>`, commit only documentation
         changes, push, and open a PR with `gh pr create`. Never touch .nix files.
      4. Do not force-push, do not touch main, do not amend existing commits.
    '';
  };
}
```

The "work items under a user story" variant is the same shape with `az boards
work-item create` on `PATH` and an ADO PAT in `credentials` — reuses
`modules/work/azure.nix` and the existing `pi-azure-devops` extension.

Prompt-hygiene rules worth baking into `piAgent.defaults.appendSystemPrompt` for
every job (unattended agents need explicit stop conditions):
*no interactive prompts; never force-push; never push to a default branch; if the
task appears already done, exit without changes; if blocked, report and stop.*

---

## 7. Testing it without deploying it

Three tiers, cheapest first. **Tiers 1 and 2 are implemented; tier 3 is deferred.**

1. **Eval/build.** `nix build .#pi-daemon` and `nix build .#checks.x86_64-linux.pi-agent-eval`.
   The latter evaluates a throwaway `nixosSystem` carrying the bucket with the
   example job forced on, then forces the parts that actually break: assertions,
   the rendered unit text (`$out/units.txt`), and every runner derivation (whose
   build runs shellcheck). Seconds, no host touched.
2. **Run the runner directly.** Each job's runner is exposed as a package:

   ```sh
   nix build .#pi-agent-runner-<job>
   PI_AGENT_STATE_DIR=$PWD/state PI_CODING_AGENT_DIR=$HOME/.pi/agent \
     ./result/bin/pi-agent-<job>
   ```

   Exercises the real clone → prompt → pi → summarize path against your own
   creds, no systemd, no root. This is the fast iteration loop, and it is how the
   `checkout -f` bug above was found.
3. **NixOS VM test** (deferred) — `pkgs.testers.runNixOSTest`, exposed as
   `flake.checks.<system>.pi-agent`:
   - a stub `pi` on `PATH` that emits a canned `--mode json` stream (no network, no
     API key, deterministic),
   - a local git repo served over `file://` as the job's `repo.url`,
   - assertions: the timer exists, `systemctl start pi-agent-<n>` succeeds, a
     `runs/*.jsonl` was written, the workspace was reset to `origin/main`, the unit
     ran as `pi-agent`, and `/home` was genuinely inaccessible.

   That last point is the real value — it proves the hardening block is correct
   before it ever guards a live API token.

Optionally a fourth: one **live smoke job** on a scratch repo with a
5-minute `OnCalendar`, run once by hand on hilbert before trusting a nightly.

---

## 8. Deferred (phase 2+)

- **The VM test** described in tier 3 above — the one thing from phase 1 that did
  not land. It is the only way to *prove* the hardening block (especially that
  `/home` is inaccessible and that Node's JIT survives) before it guards a live
  token.
- **Webhook triggers** — `systemd.sockets` + a tiny HTTP shim so Forgejo/GitHub/ADO
  can fire a job on PR-opened. Needs auth on the endpoint; keep it behind wireguard.
- **Inbox / path units** — drop a markdown task file into
  `/var/lib/pi-agent/inbox`, a `.path` unit picks it up. Nice for chaining from
  other tools.
- **Per-job container isolation** — swap the systemd sandbox for podman when a job
  must run untrusted code. The option schema above is already container-shaped
  (`packages`, `environment`, `credentials`, `workdir`).
- **Concurrency** — replace the global `flock` with per-job agent dirs once
  auth can be provisioned non-interactively.
- **Cost/observability** — parse `--mode json` for token usage per run, expose as a
  textfile-collector metric.

## 9. Open risks

| Risk | Mitigation |
| --- | --- |
| Job hangs on an interactive extension | interactive extensions excluded from `pi-daemon`; `excludeTools` defaults; `TimeoutStartSec` |
| OAuth token rotation logs you out | daemon gets its own `/login` grant, never shares your `auth.json` |
| Agent pushes to `main` / force-pushes | explicit stop conditions in `defaults.appendSystemPrompt`; branch protection on the forge; `--tools` allowlist |
| Prompt injection from repo content | `--approve` off by default; per-job tool allowlist; systemd sandbox; PR review before merge |
| Runaway token spend | `RandomizedDelaySec` + `Persistent` won't stampede; add a per-run timeout and (later) usage metrics |
| Node JIT killed by hardening | `MemoryDenyWriteExecute=false`, asserted by the VM test |
