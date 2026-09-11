import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

// Use the unwrapped Pi executable, so this test loads only the bridge from
// source. Set PI_TEST_BINARY to test Node or the standalone Bun package.
test("Pi loads the bridge and registers its commands", {
  skip: !process.env.PI_TEST_BINARY && "Set PI_TEST_BINARY to an unwrapped Pi executable",
}, async () => {
  const home = await mkdtemp(join(tmpdir(), "pi-edge-startup-"));
  try {
    const result = spawnSync(process.env.PI_TEST_BINARY, [
      "--mode", "rpc", "--no-session", "--offline", "--no-approve",
      "--no-extensions", "--no-skills", "--no-prompt-templates",
      "--no-themes", "--no-context-files",
      "--extension", fileURLToPath(new URL("../src/index.ts", import.meta.url)),
    ], {
      cwd: home,
      env: {
        PATH: process.env.PATH,
        HOME: home,
        XDG_CONFIG_HOME: join(home, "config"),
        XDG_CACHE_HOME: join(home, "cache"),
        XDG_DATA_HOME: join(home, "data"),
        PI_CODING_AGENT_DIR: join(home, "agent"),
        PI_OFFLINE: "1",
        PI_TELEMETRY: "0",
        TERM: "dumb",
      },
      input: '{"id":"commands","type":"get_commands"}\n',
      encoding: "utf8",
      timeout: 20_000,
      maxBuffer: 1024 * 1024,
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr.slice(0, 600));
    const events = result.stdout.trim().split("\n").map(line => JSON.parse(line));
    const response = events.find(event => event.type === "response" && event.id === "commands");
    assert.equal(response?.success, true, "Pi must answer the RPC command after loading extensions");
    for (const name of ["ab-edge-status", "ab-edge-reset"]) {
      assert(response.data.commands.some(command => command.source === "extension" && command.name === name), `Missing /${name}`);
    }
    assert(!events.some(event => event.type === "extension_error"));
  } finally {
    await rm(home, { recursive: true, force: true });
  }
});
