# Proposal: pull more of `numtide/llm-agents.nix` into nixdots

## Current state (what I found)

- `flake.nix` already pins `github:numtide/llm-agents.nix`, but the lock is at `707fa39a…`; a newer rev (`5b08235a…`, 2026-08-01) exists.
- The only thing currently consumed from it is `inputs.llm-agents.packages.${system}.pi` (used in the `pi-desktop`/`pi-wsl` wrappers and exposed as `.#pi-upstream`).
- `opencode`, `aider-chat`, etc. are taken from nixpkgs; `github-copilot-cli` is maintained by a manual overlay (`overlays/github-copilot-cli.nix`).
- `overlays/agent-mcps/default.nix` still imports `modules/home/ai/lib.nix`, which no longer exists (the module moved to `modules/ai/lib.nix`).
- You already have a custom skill/pi-extension deployment scheme under `modules/agents/` and `modules/ai/extensions/`.

## What `llm-agents.nix` actually offers

`numtide/llm-agents.nix` is a large, auto-updated package set. Roughly, the interesting buckets are:

| Bucket | Examples |
| --- | --- |
| **Terminal coding agents** | `pi`, `opencode`, `opencode2`, `claude-code`, `codex`, `gemini-cli`, `goose-cli`, `copilot-cli`, `crush`, `cursor-agent`, `mistral-vibe`, `kimi-code`, `qwen-code`, `reasonix`, `vix`, `zaly` |
| **Assisted browsers / terminals** | `agent-browser`, `vessel-browser`, `terminal-use` |
| **Review / diff / audit** | `hunk`, `tuicr`, `crit`, `plannotator`, `coderabbit-cli`, `ccusage`, `agentsview`, `entire` |
| **Workflow & project mgmt** | `backlog-md`, `beads`, `spec-kit`, `openspec`, `td`, `workmux`, `vibe-kanban` |
| **Memory & context** | `gno`, `icm`, `semble`, `codegraph`, `ck`, `zat`, `lean-ctx`, `context-hub` |
| **MCP / proxy / utility** | `mcporter`, `cli-proxy-api`, `rtk`, `ax`, `git-surgeon` |
| **Skills & plugins** | `openskills`, `skills`, `skills-installer`, `claude-plugins` |
| **Nix helpers** | `bun2nix`, `buildNpmPackage` wrapper, `formatelf`, `versionCheckHomeHook` |

Relevant outputs for us:

- `inputs.llm-agents.packages.<system>.<name>` — pre-built against Numtide’s locked nixpkgs (best binary-cache hit rate).
- `inputs.llm-agents.overlays.shared-nixpkgs` — adds `pkgs.llm-agents.<name>` built against *your* nixpkgs (no second nixpkgs evaluation, but may miss the public cache).
- `lib/default.nix` extends `lib.maintainers`, but that is mostly for contributors, not consumers.

## Recommended updates (in priority order)

### 1. Update the `llm-agents` flake input
Simple first win; gets latest `pi`, `opencode`, `copilot-cli`, etc.

```bash
nix flake lock --update-input llm-agents
```

### 2. Stop hand-maintaining `github-copilot-cli`; use `llm-agents`’s `copilot-cli`
Numtide’s package already pins the latest `@github/copilot` per-platform package, disables auto-update, and handles the Node SEA quirks. You can delete `overlays/github-copilot-cli.nix` and change `modules/ai/_impl/copilot-cli.nix` to use:

```nix
pkgs.llm-agents.copilot-cli      # if you add the overlay
# or
inputs.llm-agents.packages.${pkgs.system}.copilot-cli
```

### 3. Choose an access style

**Option A — overlay (cleaner call-sites):**

```nix
# modules/system/nix.nix
nixpkgs.overlays = [
  inputs.llm-agents.overlays.shared-nixpkgs
];
```

Then everywhere: `pkgs.llm-agents.opencode`, `pkgs.llm-agents.codex`, `pkgs.llm-agents.claude-code`, etc.

**Option B — direct references (better cache hit):**
Keep the current pattern and just reference `inputs.llm-agents.packages.${pkgs.system}.<name>`. No extra builds against your nixpkgs, so you’re more likely to hit Numtide’s cache.

**My recommendation:** start with Option B for agents you use daily, and only add the overlay if you find yourself writing `inputs.llm-agents.packages.${pkgs.system}.X` in five places.

### 4. Add a declarative agent roster

Instead of one-off `my.ai.opencode.enable`, `my.ai.aider.enable`, etc., consider one option set:

```nix
# modules/ai/_impl/agents.nix (new file)
{ config, pkgs, lib, inputs, ... }:
let
  cfg = config.my.ai;
  la = inputs.llm-agents.packages.${pkgs.system};   # or pkgs.llm-agents

  agentPkgs = {
    opencode      = la.opencode;
    codex         = la.codex;
    claude-code   = la.claude-code;
    gemini-cli    = la.gemini-cli;
    goose-cli     = la.goose-cli;
    copilot-cli   = la.copilot-cli;
    crush         = la.crush;
    mistral-vibe  = la.mistral-vibe;
    kimi-code     = la.kimi-code;
    # aider is not in llm-agents; keep pkgs.aider-chat
  };
in
{
  options.my.ai.agents = lib.mapAttrs (name: pkg:
    lib.mkEnableOption "install ${name} from llm-agents.nix"
  ) agentPkgs;

  config.home.packages = lib.mkIf cfg.enable (
    lib.attrValues (lib.filterAttrs (n: _: cfg.agents.${n}) agentPkgs)
  );
}
```

Then your host bucket can do `my.ai.agents.codex = true;` without touching `home.packages` directly.

### 5. Integrate extra tooling into the buckets you already use

| Your bucket | Tool to add | Why |
| --- | --- | --- |
| `ai` / `pi` wrappers | `agent-browser`, `vessel-browser`, `terminal-use` | richer headless browser / terminal automation for `pi` |
| `ai` | `openskills`, `skills` | load Anthropic/`SKILL.md`-style skills across agents, complementing your existing skill deployment |
| `shell/tmux` or `desktop-core` | `workmux` | git worktree + tmux window orchestration |
| `development/git` | `git-surgeon`, `but`, `gitbutler` | git primitives / stacked branches for agent workflows |
| `pkgs` / devShell | `hunk`, `tuicr`, `crit` | review agent-generated diffs |
| `development` / devShell | `backlog-md`, `openspec`, `spec-kit` | spec-driven / project collaboration helpers |
| devShell | `gno`, `semble`, `zat` | local semantic search / code outline for context gathering |

Concretely, your `modules/flake/devshell.nix` could become the “repo agent toolkit”:

```nix
devShells.default = pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    bashInteractive nodejs sops
    inputs.llm-agents.packages.${system}.agent-browser
    inputs.llm-agents.packages.${system}.hunk
    inputs.llm-agents.packages.${system}.crit
    inputs.llm-agents.packages.${system}.tuicr
    inputs.llm-agents.packages.${system}.gno
    inputs.llm-agents.packages.${system}.zat
  ];
};
```

### 6. Replace the `hunk` flake input with `llm-agents`
You already depend on `github:modem-dev/hunk` as an input. You can likely drop it and use `inputs.llm-agents.packages.${system}.hunk` instead, trimming the lockfile.

### 7. Fix the stale MCP overlay path
`overlays/agent-mcps/default.nix` imports `../../modules/home/ai/lib.nix`. It should be `../../modules/ai/lib.nix`. Fixing this unblocks unifying MCP server definitions.

### 8. Optional: add a Numtide-fed `pi-upstream`
`modules/flake/packages.nix` exposes `.#pi-upstream` via `inputs.llm-agents.packages.${system}.pi`. If you go with Option A (overlay), this becomes:

```nix
packages = {
  pi-upstream = pkgs.llm-agents.pi;
};
```

## Suggested first milestone (smallest useful change)

1. `nix flake lock --update-input llm-agents`
2. Fix `overlays/agent-mcps/default.nix` import path.
3. Replace `github-copilot-cli` overlay with `inputs.llm-agents.packages.${pkgs.system}.copilot-cli`.
4. Add `opencode` and `codex` from `llm-agents` behind new `my.ai.agents.*` options.
5. Drop the `hunk` input and use `inputs.llm-agents.packages.${system}.hunk`.

That alone removes two overlays/inputs, centralizes agent versioning, and gives you a clean place to add the rest.

## Next steps

Tell me which tier you want and I’ll start implementing:

- **Tier 1:** just the milestone above (update + copilot/hunk cleanup + a couple agents).
- **Tier 2:** add the `my.ai.agents` roster and wire up 6–8 agents plus the devShell toolkit.
- **Tier 3:** full integration — overlay, skill managers (`openskills`/`skills`), browser/terminal tools, review tools, and memory/context packages.
