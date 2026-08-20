# Runner-script builder for the `pi-agent` daemon (see ../pi-agent.nix).
#
# Not a flake-parts module: the leading `_` in the path keeps it out of
# import-tree. It is a plain function called from the nixos bucket with the
# host's `pkgs`, so the script it returns is also a normal derivation that can
# be run BY HAND, outside systemd:
#
#   PI_AGENT_STATE_DIR=$PWD/state ./result/bin/pi-agent-<name>
#
# which is the fast iteration loop for a new job.
{
  pkgs,
  lib,
  name,
  job,
  stateDir,
  piPackage,
}:
let
  promptFile =
    if job.promptFile != null then
      job.promptFile
    else
      pkgs.writeText "pi-agent-${name}-prompt" job.prompt;

  appendPromptFile =
    if job.appendSystemPrompt == "" then
      null
    else
      pkgs.writeText "pi-agent-${name}-system-prompt" job.appendSystemPrompt;

  # Turns the json event stream into a few readable journald lines. Kept in a
  # file rather than inline so the shell quoting stays sane.
  summarize = pkgs.writeText "pi-agent-summarize.jq" ''
    fromjson?
    | if .type == "session" then "session \(.id // "?")"
      elif .type == "tool_execution_start" then "-> \(.toolName)"
      elif .type == "tool_execution_end" and .isError then "!! \(.toolName) returned an error"
      elif .type == "message_end" and (.message.role? == "assistant") then
        ([.message.content[]? | select(.type == "text") | .text] | join("") | select(length > 0))
      elif .type == "agent_end" then "<- agent_end"
      else empty
      end
  '';

  piFlags = [
    "--mode"
    "json"
  ]
  ++ lib.optionals (job.model != null) [
    "--model"
    job.model
  ]
  ++ lib.optionals (job.thinking != null) [
    "--thinking"
    job.thinking
  ]
  ++ lib.optionals (job.tools != [ ]) [
    "--tools"
    (lib.concatStringsSep "," job.tools)
  ]
  ++ lib.optionals (job.excludeTools != [ ]) [
    "--exclude-tools"
    (lib.concatStringsSep "," job.excludeTools)
  ]
  ++ lib.concatMap (e: [
    "--extension"
    (toString e)
  ]) job.extraExtensions
  ++ lib.concatMap (s: [
    "--skill"
    (toString s)
  ]) job.skills
  ++ lib.optionals (appendPromptFile != null) [
    "--append-system-prompt"
    (toString appendPromptFile)
  ]
  ++ lib.optional job.approveProject "--approve";

  gitSync = lib.optionalString (job.repo != null) (
    let
      depth = lib.optionalString (job.repo.depth != null) "--depth ${toString job.repo.depth}";
    in
    ''
      # --- deterministic workspace ------------------------------------------
      # Every run starts from a pristine origin/<ref>; nothing an earlier run
      # left behind can influence this one.
      if [ -d "$WORKDIR/.git" ]; then
        git -C "$WORKDIR" remote set-url origin ${lib.escapeShellArg job.repo.url}
        git -C "$WORKDIR" fetch --prune ${depth} origin ${lib.escapeShellArg job.repo.ref}
      else
        find "$WORKDIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        git clone ${depth} --branch ${lib.escapeShellArg job.repo.ref} \
          ${lib.escapeShellArg job.repo.url} "$WORKDIR"
      fi
      # `-f`: the previous run may have left a dirty tree or an unrelated
      # branch checked out; a plain checkout would refuse.
      git -C "$WORKDIR" checkout -f -B ${lib.escapeShellArg job.repo.ref} \
        "origin/${job.repo.ref}"
      git -C "$WORKDIR" reset --hard "origin/${job.repo.ref}"
      git -C "$WORKDIR" clean -fdx
      echo "workspace at $(git -C "$WORKDIR" rev-parse --short HEAD)"
    ''
  );

  runDir = lib.optionalString (job.repo != null && job.repo.subdir != null) "/${job.repo.subdir}";
in
pkgs.writeShellApplication {
  name = "pi-agent-${name}";

  runtimeInputs = [
    piPackage
    pkgs.coreutils
    pkgs.findutils
    pkgs.git
    pkgs.jq
    pkgs.util-linux # flock
  ]
  ++ job.packages;

  # `set -euo pipefail` is supplied by writeShellApplication.
  text = ''
    STATE_DIR="''${PI_AGENT_STATE_DIR:-${stateDir}}"
    JOB_DIR="$STATE_DIR/jobs/${name}"
    WORKDIR="$JOB_DIR/work"
    RUNS_DIR="$JOB_DIR/runs"
    SESSION_DIR="$JOB_DIR/sessions"
    AGENT_DIR="''${PI_CODING_AGENT_DIR:-$STATE_DIR/agent}"
    export PI_CODING_AGENT_DIR="$AGENT_DIR"
    export HOME="''${HOME:-$STATE_DIR}"

    # An unattended agent must never sit at a credential prompt.
    export GIT_TERMINAL_PROMPT=0
    : "''${GIT_AUTHOR_NAME:=pi-agent}"
    : "''${GIT_AUTHOR_EMAIL:=pi-agent@localhost}"
    : "''${GIT_COMMITTER_NAME:=$GIT_AUTHOR_NAME}"
    : "''${GIT_COMMITTER_EMAIL:=$GIT_AUTHOR_EMAIL}"
    export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

    mkdir -p "$AGENT_DIR" "$WORKDIR" "$RUNS_DIR" "$SESSION_DIR"

    RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
    RUN_LOG="$RUNS_DIR/$RUN_ID.jsonl"
    export RUN_ID RUN_LOG WORKDIR JOB_DIR

    # Serialize every pi invocation on this host: concurrent jobs would
    # otherwise race on auth.json refresh and the hermes-memory sqlite lock.
    exec 9>"$AGENT_DIR/.pi-agent.lock"
    flock 9

    echo "pi-agent/${name}: run $RUN_ID"

    ${gitSync}
    ${lib.optionalString (job.preRun != "") ''
      # --- preRun -----------------------------------------------------------
      ${job.preRun}
    ''}

    cd "$WORKDIR${runDir}"

    rc=0
    # pi has no `--` separator: the prompt is a positional message, so it must
    # not start with `-` (the module asserts that).
    pi ${lib.escapeShellArgs piFlags} \
      --session-dir "$SESSION_DIR" \
      --name "${name} $RUN_ID" \
      "$(cat ${toString promptFile})" \
      | tee "$RUN_LOG" \
      | jq -Rr --unbuffered -f ${summarize} || rc=$?

    # A clean exit code is necessary but not sufficient: a stream without
    # `agent_end` means the run died mid-turn.
    ended=$(jq -Rr 'fromjson? | select(.type == "agent_end") | "x"' "$RUN_LOG" | wc -l)
    toolErrors=$(jq -Rr 'fromjson? | select(.type == "tool_execution_end" and .isError == true) | .toolName' "$RUN_LOG" | wc -l)
    echo "pi-agent/${name}: exit=$rc agent_end=$ended tool_errors=$toolErrors log=$RUN_LOG"

    ${lib.optionalString (job.postRun != "") ''
      # --- postRun ----------------------------------------------------------
      ${job.postRun}
    ''}

    # Keep the last ${toString job.keepRuns} transcripts.
    find "$RUNS_DIR" -maxdepth 1 -name '*.jsonl' -printf '%T@ %p\n' \
      | sort -rn \
      | tail -n +${toString (job.keepRuns + 1)} \
      | cut -d' ' -f2- \
      | xargs -r rm -f

    if [ "$rc" -ne 0 ]; then
      echo "pi-agent/${name}: pi exited $rc" >&2
      exit "$rc"
    fi
    if [ "$ended" -eq 0 ]; then
      echo "pi-agent/${name}: stream ended without agent_end" >&2
      exit 1
    fi
  '';

  meta.description = "Unattended pi run for the '${name}' pi-agent job";
}
