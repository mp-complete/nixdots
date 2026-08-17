export interface EdgeCdpVersion {
  Browser?: unknown;
  webSocketDebuggerUrl?: unknown;
}

export interface EdgeCdpEndpoint {
  browser: string;
  httpUrl: string;
  identity: string;
  wsUrl: string;
}

/**
 * Keep the verified browser path but replace the host reported by Windows Edge
 * with the exact HTTP endpoint that WSL proved reachable.
 */
export function resolveReachableEdgeEndpoint(
  reachableUrl: string,
  version: EdgeCdpVersion,
): EdgeCdpEndpoint | null {
  let reachable: URL;
  let reportedWebSocket: URL;
  try {
    reachable = new URL(reachableUrl);
    reportedWebSocket = new URL(String(version.webSocketDebuggerUrl));
  } catch {
    return null;
  }

  if (
    !["http:", "https:"].includes(reachable.protocol) ||
    reachable.username ||
    reachable.password ||
    reachable.pathname !== "/" ||
    reachable.search ||
    reachable.hash ||
    typeof version.Browser !== "string" ||
    !/^Edg\//.test(version.Browser) ||
    !["ws:", "wss:"].includes(reportedWebSocket.protocol) ||
    !/^\/devtools\/browser\/[^/?#]+$/.test(reportedWebSocket.pathname)
  ) {
    return null;
  }

  const websocket = new URL(reachable.origin);
  websocket.protocol = reachable.protocol === "https:" ? "wss:" : "ws:";
  websocket.pathname = reportedWebSocket.pathname;

  return {
    browser: version.Browser,
    httpUrl: reachable.origin,
    identity: `${version.Browser}\t${reportedWebSocket.pathname}`,
    wsUrl: websocket.toString(),
  };
}
