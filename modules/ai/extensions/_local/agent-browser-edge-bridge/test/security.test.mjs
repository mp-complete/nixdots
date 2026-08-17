import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const controller = await readFile(
  new URL("../scripts/edge_bridge.ps1", import.meta.url),
  "utf8",
);
const forwarder = await readFile(
  new URL("../scripts/cdp_forwarder.ps1", import.meta.url),
  "utf8",
);
const bootstrap = await readFile(
  new URL("../scripts/bootstrap.sh", import.meta.url),
  "utf8",
);
const extension = await readFile(
  new URL("../src/index.ts", import.meta.url),
  "utf8",
);

test("the NAT relay cannot construct a wildcard listener", () => {
  assert.doesNotMatch(forwarder, /new TcpListener\(IPAddress\.(Any|IPv6Any)/);
  assert.match(forwarder, /IPAddress\.Parse\(listenAddress\)/);
  assert.match(forwarder, /Wildcard listen addresses are prohibited/);
  assert.match(controller, /Get-FileHash -LiteralPath \$runningForwarderPath/);
  assert.match(bootstrap, /FORWARDER_HASH=/);
});

test("the verified Edge debug listener must stay on loopback", () => {
  assert.match(controller, /LocalAddress -notin @\('127\.0\.0\.1', '::1'\)/);
  assert.match(controller, /CommandLineToArgvW/);
  assert.match(controller, /\$portValues\.Count -ne 1/);
  assert.match(controller, /\$profileValues\.Count -ne 1/);
  assert.match(controller, /Get-EdgeCdpIdentity/);
});

test("bootstrap prefers mirrored localhost before NAT", () => {
  const directProbe = bootstrap.indexOf('DIRECT_URL="http://127.0.0.1:');
  const gatewayLookup = bootstrap.indexOf("ip route show default");
  assert.ok(directProbe >= 0);
  assert.ok(gatewayLookup > directProbe);
});

test("the reachable endpoint must match the verified Windows Edge identity", () => {
  assert.match(bootstrap, /EXPECTED_EDGE_IDENTITY/);
  assert.match(bootstrap, /probe_expected_edge/);
  assert.match(bootstrap, /webSocketDebuggerUrl/);
});

test("each Pi runtime revalidates ownership and installs only the verified Edge endpoint", () => {
  assert.doesNotMatch(extension, /pi-agent-browser-cdp-url|readCachedUrl|writeCachedUrl/);
  assert.match(extension, /event\.toolName !== "browser_execute"/);
  assert.match(extension, /current\?\.identity === bridgeEndpoint\.identity/);
  assert.match(extension, /process\.env\[CDP_WS_ENV\] = endpoint\.wsUrl/);
  assert.match(extension, /delete process\.env\[CDP_URL_ENV\]/);
});
