import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  type EdgeCdpEndpoint,
  resolveReachableEdgeEndpoint,
} from "./cdp-endpoint.ts";

const here =
  (import.meta as { dirname?: string }).dirname ??
  dirname(fileURLToPath(import.meta.url));
const BOOTSTRAP_SH = resolve(here, "..", "scripts", "bootstrap.sh");

const STATUS_KEY = "ab-edge-bridge";
const BOOTSTRAP_TIMEOUT_MS = 150_000;
const PROBE_TIMEOUT_MS = 3_000;
const FAILURE_BACKOFF_MS = 30_000;
const CDP_WS_ENV = "BU_CDP_WS";
const CDP_URL_ENV = "BU_CDP_URL";

interface ExecLike {
  stdout: string;
  stderr: string;
  code: number;
}

function lastNonEmptyLine(value: string): string {
  const lines = value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  return lines[lines.length - 1] ?? "";
}

function formatExecFailure(label: string, result: ExecLike): string {
  const tail = (result.stderr || result.stdout || "")
    .trim()
    .split(/\r?\n/)
    .slice(-14)
    .join("\n");
  return `${label} failed (exit ${result.code})${tail ? `:\n${tail}` : ""}`;
}

function formatBootstrapFailure(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return [
    "Windows Edge CDP bootstrap failed. browser_execute was not executed.",
    "",
    message,
    "",
    "The failure is reported by its layer (Edge policy, Windows process launch,",
    "debug-port ownership, NAT forwarder, or WSL reachability). Useful checks:",
    "  • Run /ab-edge-status, then /ab-edge-reset before retrying changed setup.",
    "  • In Windows Edge, inspect edge://policy and RemoteDebuggingAllowed.",
    "  • On Windows, inspect ports 9222/9223 with Get-NetTCPConnection and",
    "    their owning Win32_Process command lines before stopping anything.",
    "  • The dedicated visible profile is under LocalAppData\\Microsoft\\Edge\\",
    "    User Data - CDP unless WSL_BROWSER_USER_DATA_DIR overrides it.",
    "",
    "/ab-edge-reset forgets Pi bridge state only; it does not stop Edge or",
    "PowerShell processes.",
  ].join("\n");
}

function formatBackoffMessage(remainingMs: number): string {
  const remainingSeconds = Math.max(1, Math.ceil(remainingMs / 1000));
  return [
    `Windows Edge bootstrap failed recently; cooling down for ~${remainingSeconds}s.`,
    "Run /ab-edge-reset to retry immediately after correcting the reported layer.",
  ].join("\n");
}

async function probeCdpEndpoint(url: string): Promise<EdgeCdpEndpoint | null> {
  try {
    const response = await fetch(`${url}/json/version`, {
      signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
    });
    if (!response.ok) return null;
    return resolveReachableEdgeEndpoint(
      url,
      (await response.json()) as {
        Browser?: unknown;
        webSocketDebuggerUrl?: unknown;
      },
    );
  } catch {
    return null;
  }
}

export default function edgeCdpBridgeExtension(pi: ExtensionAPI) {
  let bridge: Promise<EdgeCdpEndpoint> | null = null;
  let bridgeEndpoint: EdgeCdpEndpoint | null = null;
  let lastFailureAt: number | null = null;

  // This WSL wrapper is Edge-only. Ignore ambient pi-chrome-use endpoint
  // selection until the bridge has verified and installed its own endpoint.
  delete process.env[CDP_WS_ENV];
  delete process.env[CDP_URL_ENV];

  function clearEndpoint(): void {
    if (process.env[CDP_WS_ENV] === bridgeEndpoint?.wsUrl) {
      delete process.env[CDP_WS_ENV];
    }
    delete process.env[CDP_URL_ENV];
    bridge = null;
    bridgeEndpoint = null;
  }

  function installEndpoint(endpoint: EdgeCdpEndpoint): void {
    process.env[CDP_WS_ENV] = endpoint.wsUrl;
    delete process.env[CDP_URL_ENV];
    bridgeEndpoint = endpoint;
  }

  async function runBootstrap(ctx: ExtensionContext): Promise<EdgeCdpEndpoint> {
    ctx.ui.setStatus(STATUS_KEY, "Edge CDP: checking policy and Windows Edge…");
    const result = (await pi.exec("bash", [BOOTSTRAP_SH], {
      timeout: BOOTSTRAP_TIMEOUT_MS,
    })) as ExecLike;
    if (result.code !== 0) {
      throw new Error(formatExecFailure(`bootstrap.sh (${BOOTSTRAP_SH})`, result));
    }

    const cdpUrl = lastNonEmptyLine(result.stdout);
    const endpoint = /^https?:\/\//.test(cdpUrl)
      ? await probeCdpEndpoint(cdpUrl)
      : null;
    if (!endpoint) {
      throw new Error(
        `bootstrap.sh returned ${JSON.stringify(cdpUrl)}, but it is not a reachable Microsoft Edge CDP endpoint.`,
      );
    }
    return endpoint;
  }

  function ensureBridge(ctx: ExtensionContext): Promise<EdgeCdpEndpoint> {
    if (bridge) return bridge;

    if (lastFailureAt !== null) {
      const elapsed = Date.now() - lastFailureAt;
      if (elapsed < FAILURE_BACKOFF_MS) {
        return Promise.reject(
          new Error(formatBackoffMessage(FAILURE_BACKOFF_MS - elapsed)),
        );
      }
      lastFailureAt = null;
    }

    bridge = runBootstrap(ctx).then(
      (endpoint) => {
        installEndpoint(endpoint);
        lastFailureAt = null;
        ctx.ui.setStatus(STATUS_KEY, `Edge CDP: ready (${endpoint.browser})`);
        return endpoint;
      },
      (error) => {
        clearEndpoint();
        lastFailureAt = Date.now();
        ctx.ui.setStatus(STATUS_KEY, "Edge CDP: failed");
        throw error;
      },
    );
    return bridge;
  }

  async function ensureCurrentBridge(
    ctx: ExtensionContext,
  ): Promise<EdgeCdpEndpoint> {
    if (bridgeEndpoint) {
      const current = await probeCdpEndpoint(bridgeEndpoint.httpUrl);
      if (current?.identity === bridgeEndpoint.identity) {
        installEndpoint(current);
        return current;
      }
      clearEndpoint();
    }
    return await ensureBridge(ctx);
  }

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "browser_execute") return;

    try {
      await ensureCurrentBridge(ctx);
    } catch (error) {
      return {
        block: true,
        reason: formatBootstrapFailure(error),
      };
    }
  });

  pi.registerCommand("ab-edge-status", {
    description: "Show the Edge-only CDP bridge status",
    handler: async (_args, ctx) => {
      const lines = [
        "Browser backend: Windows Edge CDP (WSL wrapper, edge-only)",
        `Endpoint: ${bridgeEndpoint?.httpUrl ?? "not established in this Pi runtime"}`,
        `Identity: ${bridgeEndpoint?.browser ?? "unverified"}`,
        `pi-chrome-use environment: ${process.env[CDP_WS_ENV] ? "configured" : "not configured"}`,
      ];
      if (lastFailureAt !== null) {
        const remaining = FAILURE_BACKOFF_MS - (Date.now() - lastFailureAt);
        if (remaining > 0) {
          lines.push(`Bootstrap cooldown: ${Math.ceil(remaining / 1000)}s`);
        }
      }
      ctx.ui.notify(lines.join("\n"), "info");
    },
  });

  pi.registerCommand("ab-edge-reset", {
    description: "Forget Edge CDP bridge state (does not stop Windows processes)",
    handler: async (_args, ctx) => {
      clearEndpoint();
      lastFailureAt = null;
      ctx.ui.setStatus(STATUS_KEY, "Edge CDP: reset; next browser call revalidates");
      ctx.ui.notify(
        "Reset Pi Edge CDP state. No Edge or PowerShell process was stopped; the next browser_execute call will re-bootstrap and revalidate the dedicated Edge profile.",
        "info",
      );
    },
  });
}
