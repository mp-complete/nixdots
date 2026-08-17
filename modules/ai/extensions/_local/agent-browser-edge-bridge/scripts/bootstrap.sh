#!/usr/bin/env bash
# Ensure a dedicated visible Microsoft Edge work profile is running on Windows
# and return a WSL-reachable CDP URL. Diagnostics go to stderr; the final stdout
# line is the URL consumed by the Pi extension.
set -euo pipefail

DEBUG_PORT="${WSL_BROWSER_DEBUG_PORT:-9222}"
FORWARD_PORT="${WSL_BROWSER_FORWARD_PORT:-9223}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROLLER_SRC="$SCRIPT_DIR/edge_bridge.ps1"
FORWARDER_SRC="$SCRIPT_DIR/cdp_forwarder.ps1"

log() { printf '[wsl-edge] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

[[ "$DEBUG_PORT" =~ ^[0-9]+$ ]] && (( DEBUG_PORT > 0 && DEBUG_PORT < 65536 )) \
  || die "WSL_BROWSER_DEBUG_PORT must be a TCP port number."
[[ "$FORWARD_PORT" =~ ^[0-9]+$ ]] && (( FORWARD_PORT > 0 && FORWARD_PORT < 65536 )) \
  || die "WSL_BROWSER_FORWARD_PORT must be a TCP port number."
[[ "$DEBUG_PORT" != "$FORWARD_PORT" ]] || die "Debug and forward ports must differ."

grep -qi microsoft /proc/version 2>/dev/null \
  || die "WSL detection failed; this bridge only runs inside WSL2."
for command in powershell.exe cmd.exe wslpath curl jq sha256sum; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required but not on PATH."
done

edge_identity() {
  local url="$1"
  local payload
  payload="$(curl -fsS --max-time 2 "$url/json/version" 2>/dev/null)" || return 1
  jq -er '[
    .Browser,
    (.webSocketDebuggerUrl
      | capture("^[^:]+://[^/]+(?<path>/devtools/browser/[^/?]+)(?:[?#].*)?$").path)
  ] | select((.[0] | type == "string") and (.[0] | startswith("Edg/"))) | @tsv' \
    <<<"$payload" 2>/dev/null
}

probe_expected_edge() {
  local url="$1"
  local actual
  actual="$(edge_identity "$url")" || return 1
  [[ "$actual" == "$EXPECTED_EDGE_IDENTITY" ]]
}

WIN_TEMP_RAW="$(cmd.exe /d /c 'echo %TEMP%' 2>/dev/null | tr -d '\r\n')"
[[ -n "$WIN_TEMP_RAW" && "$WIN_TEMP_RAW" != '%TEMP%' ]] \
  || die "Windows TEMP could not be resolved through cmd.exe."
WIN_TEMP_WSL="$(wslpath -u "$WIN_TEMP_RAW" 2>/dev/null)" \
  || die "Could not convert Windows TEMP to a WSL path: $WIN_TEMP_RAW"
[[ -d "$WIN_TEMP_WSL" ]] || die "Windows TEMP is not mounted in WSL: $WIN_TEMP_WSL"

CONTROLLER_HASH="$(sha256sum "$CONTROLLER_SRC" | cut -c1-16)"
FORWARDER_HASH="$(sha256sum "$FORWARDER_SRC" | cut -c1-16)"
CONTROLLER_WSL="$WIN_TEMP_WSL/pi_agent_browser_edge_bridge-$CONTROLLER_HASH.ps1"
FORWARDER_WSL="$WIN_TEMP_WSL/pi_agent_browser_edge_forwarder-$FORWARDER_HASH.ps1"
cp "$CONTROLLER_SRC" "$CONTROLLER_WSL"
cp "$FORWARDER_SRC" "$FORWARDER_WSL"
CONTROLLER_WIN="$(wslpath -w "$CONTROLLER_WSL")"
FORWARDER_WIN="$(wslpath -w "$FORWARDER_WSL")"

common_args=(-DebugPort "$DEBUG_PORT")
if [[ -n "${WSL_BROWSER_EDGE_EXE:-}" ]]; then
  common_args+=(-EdgeExe "$WSL_BROWSER_EDGE_EXE")
fi
if [[ -n "${WSL_BROWSER_USER_DATA_DIR:-}" ]]; then
  common_args+=(-UserDataDir "$WSL_BROWSER_USER_DATA_DIR")
fi

log "Checking Edge policy, executable, dedicated profile, and debug-port ownership."
edge_result="$(
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -File "$CONTROLLER_WIN" -Action EnsureEdge "${common_args[@]}" \
    | tr -d '\r'
)" || die "Windows Edge setup failed (see the PowerShell layer above)."
edge_json="$(tail -n1 <<<"$edge_result")"
EXPECTED_EDGE_IDENTITY="$(jq -er '[.browser, .webSocketPath] | @tsv' <<<"$edge_json" 2>/dev/null)" \
  || die "Windows Edge setup returned invalid CDP identity JSON: $edge_json"
log "Windows Edge ready: $edge_json"

# Mirrored networking makes Windows localhost reachable directly from WSL.
# Prefer it because it needs no cross-interface listener.
DIRECT_URL="http://127.0.0.1:$DEBUG_PORT"
for _ in $(seq 1 5); do
  if probe_expected_edge "$DIRECT_URL"; then
    log "Microsoft Edge CDP is reachable through mirrored localhost; no forwarder needed."
    printf '%s\n' "$DIRECT_URL"
    exit 0
  fi
  sleep 1
done

# NAT fallback: bind the relay only to the Windows gateway interface used by
# this WSL VM. The PowerShell controller refuses wildcard or unrelated owners.
WINDOWS_HOST="$(ip route show default | awk '/default/ {print $3; exit}')"
[[ "$WINDOWS_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "Could not determine a Windows IPv4 gateway for WSL NAT fallback."

log "Mirrored localhost is unavailable; checking narrow NAT forwarder on $WINDOWS_HOST:$FORWARD_PORT."
forward_result="$(
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -File "$CONTROLLER_WIN" -Action EnsureForwarder \
    -ForwardPort "$FORWARD_PORT" -ListenAddress "$WINDOWS_HOST" \
    -ForwarderPath "$FORWARDER_WIN" "${common_args[@]}" \
    | tr -d '\r'
)" || die "Windows NAT forwarder setup failed (see the ownership/policy layer above)."
log "NAT forwarder ready: $(tail -n1 <<<"$forward_result")"

FORWARDED_URL="http://$WINDOWS_HOST:$FORWARD_PORT"
for _ in $(seq 1 15); do
  if probe_expected_edge "$FORWARDED_URL"; then
    log "Microsoft Edge CDP is reachable from WSL through the narrow NAT forwarder."
    printf '%s\n' "$FORWARDED_URL"
    exit 0
  fi
  sleep 1
done

die "WSL reachability failed: $FORWARDED_URL/json/version did not match the verified Windows Edge browser identity."
