import assert from "node:assert/strict";
import { test } from "node:test";

import { findUnboundedScan, resolveCommand, tokenize } from "../src/detect.mjs";

const HOME = "/home/miles";
const scan = (cmd) => findUnboundedScan(cmd, { home: HOME });

test("blocks the command that motivated this extension", () => {
	const hit = scan(`find / -path /proc -prune -o -name "tmux.nix" -path "*wrapper*" -print 2>/dev/null | head`);
	assert.ok(hit, "expected a block");
	assert.equal(hit.tool, "find");
	assert.equal(hit.root, "/");
});

test("blocks scans of the nix store", () => {
	assert.ok(scan("find /nix/store -name 'television.nix'"));
	assert.ok(scan("rg 'programs.television' /nix/store"));
});

test("blocks scans of mounted Windows drives", () => {
	assert.ok(scan("find /mnt/c -name '*.ps1'"));
	assert.ok(scan("fd config /mnt"));
});

test("blocks bare home-directory walks", () => {
	assert.ok(scan("find ~ -name '*.nix'"));
	assert.ok(scan("find $HOME -name '*.nix'"));
	assert.ok(scan(`find ${HOME} -name '*.nix'`));
});

test("piping to head does not count as a bound", () => {
	assert.ok(scan("find / -name foo | head -3"));
});

test("sees through sudo and env prefixes", () => {
	assert.ok(scan("sudo find / -name foo"));
	assert.ok(scan("FOO=bar find / -name foo"));
});

test("sees through absolute binary paths", () => {
	assert.ok(scan("/run/current-system/sw/bin/find / -name foo"));
});

test("catches a scan in any segment of a pipeline", () => {
	assert.ok(scan("echo hi && rg pattern / | wc -l"));
	assert.ok(scan("OUT=$(find /nix -name x)"));
});

test("allows depth-bounded scans", () => {
	assert.equal(scan("find /nix/store -maxdepth 4 -path '*/modules/programs/television.nix'"), null);
	assert.equal(scan("fd -d 2 -t d . ~"), null);
	assert.equal(scan("rg --max-depth 2 foo /usr"), null);
	assert.equal(scan("tree -L 2 /"), null);
});

test("allows scans rooted at a specific directory", () => {
	assert.equal(scan("find /nix/store/abc-source/cable -name '*.toml'"), null);
	assert.equal(scan("rg television modules"), null);
	assert.equal(scan("fd -t f -e nix"), null);
	assert.equal(scan("find . -name '*.nix'"), null);
});

test("ignores non-scanning commands that mention dangerous roots", () => {
	assert.equal(scan("ls /nix/store"), null);
	assert.equal(scan("cat /proc/cpuinfo"), null);
	assert.equal(scan("df -h /mnt/c"), null);
	assert.equal(scan("echo /"), null);
});

test("tokenizer keeps quoted arguments intact", () => {
	assert.deepEqual(tokenize(`find . -name "two words" -print`), [
		"find",
		".",
		"-name",
		"two words",
		"-print",
	]);
});

test("resolveCommand strips assignments and wrappers", () => {
	assert.deepEqual(resolveCommand(["A=1", "sudo", "/usr/bin/rg", "foo", "/"]), {
		name: "rg",
		args: ["foo", "/"],
	});
});
