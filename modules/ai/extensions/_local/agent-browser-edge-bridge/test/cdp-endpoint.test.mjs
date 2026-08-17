import assert from "node:assert/strict";
import test from "node:test";
import { resolveReachableEdgeEndpoint } from "../src/cdp-endpoint.ts";

test("rewrites the Windows-reported websocket host to the WSL-reachable endpoint", () => {
  assert.deepEqual(
    resolveReachableEdgeEndpoint("http://172.20.0.1:9223", {
      Browser: "Edg/140.0.0.0",
      webSocketDebuggerUrl:
        "ws://127.0.0.1:9222/devtools/browser/11111111-2222-3333-4444-555555555555",
    }),
    {
      browser: "Edg/140.0.0.0",
      httpUrl: "http://172.20.0.1:9223",
      identity:
        "Edg/140.0.0.0\t/devtools/browser/11111111-2222-3333-4444-555555555555",
      wsUrl:
        "ws://172.20.0.1:9223/devtools/browser/11111111-2222-3333-4444-555555555555",
    },
  );
});

test("accepts mirrored localhost and preserves secure transport", () => {
  const endpoint = resolveReachableEdgeEndpoint("https://127.0.0.1:9222", {
    Browser: "Edg/140.0.0.0",
    webSocketDebuggerUrl: "wss://localhost:9222/devtools/browser/abc",
  });
  assert.equal(endpoint?.httpUrl, "https://127.0.0.1:9222");
  assert.equal(endpoint?.wsUrl, "wss://127.0.0.1:9222/devtools/browser/abc");
});

test("rejects non-Edge, credentialed, and malformed endpoints", () => {
  assert.equal(
    resolveReachableEdgeEndpoint("http://127.0.0.1:9222", {
      Browser: "Chrome/140.0.0.0",
      webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/browser/abc",
    }),
    null,
  );
  assert.equal(
    resolveReachableEdgeEndpoint("http://user:pass@127.0.0.1:9222", {
      Browser: "Edg/140.0.0.0",
      webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/browser/abc",
    }),
    null,
  );
  assert.equal(
    resolveReachableEdgeEndpoint("http://127.0.0.1:9222", {
      Browser: "Edg/140.0.0.0",
      webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/page/abc",
    }),
    null,
  );
});
