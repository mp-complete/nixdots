/**
 * pi-scan-guard — block unbounded filesystem scans before they run.
 *
 * Hooks `tool_call` for the bash tool and inspects the command for a
 * directory walker (find/rg/grep/fd/…) rooted at `/`, `/nix/store`,
 * `/mnt/<drive>` and friends with no depth bound.
 *
 * With a UI attached the user is asked; there are rare legitimate cases and
 * a guard with no escape hatch wedges real work. Without a UI (the pi-agent
 * daemon) it hard-blocks, since nobody is there to approve and an unattended
 * run would sit there until systemd's TimeoutStartSec kills it.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { explain, findUnboundedScan } from "./detect.mjs";

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;

		const command = event.input?.command as string | undefined;
		if (!command) return undefined;

		const hit = findUnboundedScan(command, { home: process.env.HOME });
		if (!hit) return undefined;

		const reason = explain(hit);

		if (!ctx.hasUI) {
			return { block: true, reason };
		}

		const choice = await ctx.ui.select(`${reason}\n\nRun it anyway?`, [
			"No, use a bounded query",
			"Yes, run it",
		]);

		if (choice !== "Yes, run it") {
			return { block: true, reason };
		}

		return undefined;
	});
}
