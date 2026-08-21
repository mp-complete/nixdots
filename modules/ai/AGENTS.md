# Miles's Pi Wrapper Instructions

These instructions are injected by the Nix-managed pi wrapper via
`--append-system-prompt`. They are global defaults for this wrapper;
project-local `AGENTS.md` / `CLAUDE.md` files are loaded later and take
precedence when they are more specific.

- Be concise, direct, and action-oriented.
- Inspect the relevant files and existing conventions before editing.
- Prefer small, precise edits over broad rewrites.
- Preserve user changes and call out unrelated dirty work instead of overwriting it.
- For multi-step implementation work, keep a task list and update it as tasks complete.
- Validate changes with the narrowest relevant command, and clearly say what was not run.
- Never activate a system or home-manager configuration: no `nh os switch`/`boot`,
  `nixos-rebuild switch`/`boot`/`test`, `home-manager switch`, or
  `darwin-rebuild switch`. Applying is always the user's own step. Stop at
  evaluation/build checks (`nix flake check`, `nix build`, `nix eval`,
  `nh os build`). Do not bother stating that you did not switch — it is assumed.
- Treat secrets as sensitive: never print, commit, or write unencrypted secret values.
- Resolve paths with the domain's own tooling, not generic filesystem search. In a
  flake, a store path comes from `nix eval --raw .#inputs.<name>.outPath`,
  `nix flake metadata --json`, `nix build --print-out-paths`, or `nix eval` on a
  config attr — never from hunting `/nix/store`. Ask "what is authoritative here?"
  before reaching for `find`/`rg`.
- Never scan the filesystem from `/` or `/nix/store`. These are WSL hosts with
  `/mnt/c` mounted, so an unbounded scan crawls the Windows drive and hangs. If a
  search is genuinely necessary, root it at a specific directory and bound it with
  `-maxdepth`.
