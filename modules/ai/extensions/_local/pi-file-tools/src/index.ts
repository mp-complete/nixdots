/**
 * pi-file-tools — enable pi's built-in `find`, `grep` and `ls` tools.
 *
 * Pi ships these but leaves them off: the default active set is
 * `["read", "bash", "edit", "write"]` (core/sdk.js). That default has a
 * side effect in core/system-prompt.js:
 *
 *     if (hasBash && !hasGrep && !hasFind && !hasLs) {
 *         addGuideline("Use bash for file operations like ls, rg, find");
 *     }
 *
 * …i.e. with the tools disabled the harness actively instructs the model to
 * shell out to `find`, which is how an unbounded `find /` ends up on a WSL
 * box with `/mnt/c` mounted. Turning the tools on removes that guideline and
 * replaces it with pi's own `find`, which is fd-backed, defaults to the cwd,
 * respects .gitignore, and truncates at 1000 results / 50KB.
 *
 * Why an extension rather than the `--tools` CLI flag: `--tools` sets
 * `allowedToolNames`, and core/agent-session.js filters *extension* tools
 * through the same allowlist:
 *
 *     const isAllowedTool = (name) =>
 *         (!allowedToolNames || allowedToolNames.has(name)) && !excluded?.has(name);
 *     ...
 *     ].filter((tool) => isAllowedTool(tool.definition.name));
 *
 * So `--tools read,bash,edit,write,find,grep,ls` would silently drop
 * notify_user, web_search, subagent, agent_browser and friends. Enumerating
 * every extension tool instead is brittle, since extensions register tools
 * dynamically. `setActiveTools` is purely additive and safe.
 *
 * `setActiveToolsByName` rebuilds the system prompt from the new tool set,
 * so the stale guideline really does disappear rather than lingering from
 * the initial prompt build.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** Built-in tools we want on that pi leaves off by default. */
const WANTED = ["find", "grep", "ls"] as const;

export default function (pi: ExtensionAPI) {
	pi.on("session_start", () => {
		const active = pi.getActiveTools();

		// Only enable tools that actually exist in this build, so a future pi
		// that renames or drops one degrades quietly instead of throwing.
		const available = new Set(pi.getAllTools().map((tool) => tool.name));
		const missing = WANTED.filter((name) => available.has(name) && !active.includes(name));

		if (missing.length === 0) return;

		pi.setActiveTools([...new Set([...active, ...missing])]);
	});
}
