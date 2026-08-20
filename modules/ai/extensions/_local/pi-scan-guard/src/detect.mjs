/**
 * Pure detection logic for pi-scan-guard, kept as plain ESM (not TS) so
 * `node --test` can import it directly without a TypeScript loader.
 *
 * Goal: catch unbounded filesystem scans *before* they run. On WSL hosts
 * `/mnt/c` is a mounted Windows drive, so `find /` walks two operating
 * systems and effectively hangs. The same applies to `/nix/store`, which
 * routinely holds hundreds of thousands of paths.
 *
 * Design notes:
 *   - We do NOT try to fully parse shell grammar. We split into rough
 *     segments, tokenize with quote awareness, and only inspect segments
 *     whose command is a known directory walker. False negatives are
 *     acceptable; false positives are not, because a guard that cries wolf
 *     just teaches everyone to click through it.
 *   - A depth bound anywhere in the segment clears it. `find /nix/store
 *     -maxdepth 4 …` is a legitimate, fast query.
 *   - Piping to `head` does NOT count as a bound: `find / | head` still
 *     walks the whole tree, because the directories it descends into
 *     mostly produce no output to trigger SIGPIPE.
 */

/** Commands that recursively walk directories. */
const SCANNERS = new Set([
	"find",
	"rg",
	"ripgrep",
	"grep",
	"egrep",
	"fgrep",
	"ag",
	"ack",
	"fd",
	"fdfind",
	"tree",
	"du",
	"ncdu",
]);

/** Wrappers to skip when working out what is actually being run. */
const PREFIXES = new Set([
	"sudo",
	"doas",
	"time",
	"nice",
	"ionice",
	"nohup",
	"command",
	"builtin",
	"env",
	"xargs",
	"stdbuf",
]);

/**
 * Flags that bound traversal depth. Presence of any of these in the
 * segment is taken as evidence the caller thought about cost.
 */
const DEPTH_FLAGS = [
	/^-{1,2}maxdepth(=|$)/,
	/^--max-depth(=|$)/,
	/^--max_depth(=|$)/,
	/^-d$/, // fd -d N, du -d N
	/^-L$/, // tree -L N
];

/** Roots that are never acceptable to walk in full. */
const DANGEROUS_ROOTS = [
	/^\/$/,
	/^\/nix\/?$/,
	/^\/nix\/store\/?$/,
	/^\/mnt\/?$/,
	/^\/mnt\/[a-z]\/?$/i,
	/^\/usr\/?$/,
	/^\/var\/?$/,
	/^\/proc\/?$/,
	/^\/sys\/?$/,
	/^\/home\/?$/,
	/^~\/?$/,
	/^\$HOME\/?$/,
	/^\$\{HOME\}\/?$/,
];

/**
 * Split a command line into rough execution segments. Deliberately crude:
 * we only need enough structure to attribute tokens to a command name.
 */
export function splitSegments(command) {
	return command
		.split(/\$\(|\|\||&&|[|;\n()`]/g)
		.map((s) => s.trim())
		.filter(Boolean);
}

/** Tokenize on whitespace, keeping quoted runs together, then unquote. */
export function tokenize(segment) {
	const raw = segment.match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g) ?? [];
	return raw.map((t) => t.replace(/^['"]|['"]$/g, ""));
}

/** Strip a leading path so `/nix/store/…/bin/rg` reads as `rg`. */
function basename(token) {
	const parts = token.split("/");
	return parts[parts.length - 1] ?? token;
}

/**
 * Resolve the effective command name for a segment, skipping leading
 * `VAR=value` assignments and wrapper commands like `sudo` / `xargs`.
 * Returns `{ name, args }` or null.
 */
export function resolveCommand(tokens) {
	let i = 0;
	while (i < tokens.length) {
		const tok = tokens[i];
		if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(tok)) {
			i += 1;
			continue;
		}
		const name = basename(tok);
		if (PREFIXES.has(name)) {
			i += 1;
			continue;
		}
		return { name, args: tokens.slice(i + 1) };
	}
	return null;
}

function isDangerousRoot(token, extraRoots) {
	if (DANGEROUS_ROOTS.some((re) => re.test(token))) return true;
	return extraRoots.some((root) => token === root || token === `${root}/`);
}

function hasDepthBound(args) {
	return args.some((a) => DEPTH_FLAGS.some((re) => re.test(a)));
}

/**
 * Inspect a full bash command string.
 *
 * @param {string} command
 * @param {{ home?: string }} [opts] - `home` adds the concrete home
 *   directory to the dangerous-root list (e.g. `/home/miles`).
 * @returns {{ segment: string, tool: string, root: string } | null}
 *   The first offending segment, or null when nothing looks unbounded.
 */
export function findUnboundedScan(command, opts = {}) {
	const extraRoots = [];
	if (opts.home) extraRoots.push(opts.home.replace(/\/$/, ""));

	for (const segment of splitSegments(command)) {
		const tokens = tokenize(segment);
		const resolved = resolveCommand(tokens);
		if (!resolved) continue;
		if (!SCANNERS.has(resolved.name)) continue;
		if (hasDepthBound(resolved.args)) continue;

		const root = resolved.args.find((a) => isDangerousRoot(a, extraRoots));
		if (root) {
			return { segment, tool: resolved.name, root };
		}
	}
	return null;
}

/** Human-facing explanation, written to be actionable rather than scolding. */
export function explain({ tool, root }) {
	return [
		`Unbounded filesystem scan blocked: \`${tool}\` rooted at \`${root}\`.`,
		"",
		"On these WSL hosts `/mnt/c` is a mounted Windows drive, so a scan from",
		"a root like this crawls the entire Windows filesystem and hangs.",
		"",
		"Resolve the path with the domain's own tooling instead:",
		"  • flake input      nix eval --raw .#inputs.<name>.outPath",
		"  • any lock entry   nix flake metadata --json | jq '.locks.nodes'",
		"  • package output   nix build --no-link --print-out-paths .#<attr>",
		"  • config value     nix eval --raw .#nixosConfigurations.<host>.config.<attr>",
		"",
		"If a filesystem search really is the right tool, root it at a specific",
		"directory and bound it, e.g. `find <dir> -maxdepth 3 -name '<pat>'`.",
	].join("\n");
}
