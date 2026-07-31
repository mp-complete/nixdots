---
name: pi-extensions
description: Use when the user wants to add, package, update, or remove a pi-coding-agent extension — e.g. "add the npm package X as a pi extension", "package this pi extension", "bump the pi-wsl-images extension". Covers the modules/ai/extensions registry, the pi-desktop / pi-wsl wrappers, and host wiring. Do not load for general pi usage, MCP servers, or other agents (opencode/copilot/crush/aider).
metadata:
  author: miles
  repo: ~/.config/nixdots
  version: "2.0"
---

# Packaging pi extensions in the nixos flake

In this repo a "pi extension" is a Nix derivation whose output is an
unpacked pi-package directory (a `package.json` with a `pi` manifest,
plus its `src/`, `skills/`, `prompts/`, `themes/`, …). The pi wrappers
load each one with a `--extension <store-path>` flag.

The pattern is **declarative specs, built lazily**:

- An extension is declared as **pure data** in the `pi.extensions.<name>`
  namespace — one file per extension under `modules/ai/extensions/`.
  Nothing here is a flake `packages.*` output (no pollution).
- Derivations are built on demand by `flake.lib.buildPiExtension pkgs spec`
  at **wrapper wrap-time**, using the wrapper's own pkgs.
- For debugging, every built extension is also exposed at
  `legacyPackages.<system>.piExtensions.<name>` — buildable, but hidden
  from `nix flake show`.

| File / dir | Role |
| ---------- | ---- |
| `modules/ai/extensions/registry.nix` | The engine: declares the `pi.extensions` option, defines `flake.lib.buildPiExtension`, and exposes the `legacyPackages.piExtensions` debug handle. |
| `modules/ai/extensions/<name>.nix` | One spec per extension: `pi.extensions.<name> = { … };`. Dropping a file makes the extension *available*. |
| `modules/ai/extensions/_local/<name>/` | Source for local (non-npm) extensions. `_local` keeps it out of the import tree. |
| `modules/ai/pi.nix` | The `pi-desktop` / `pi-wsl` wrappers + their extension *sets* + per-host install gating. Listing a name in a variant makes it *active*. |

> Note `registry.nix` is **not** named `_lib.nix` — import-tree skips
> any `/_` path, so the engine must have a plain name to load.

## The spec schema (`pi.extensions.<name>`)

```nix
{
  pname   = "@scope/pkg";          # npm package name (required)
  version = "1.2.3";
  hash    = "sha512-…";            # SRI of the npm tarball (registry dist.integrity)

  # optional, escalate only as needed:
  vendor  = [ { dir = "typebox"; pname = "typebox"; version = "…"; hash = "…"; } ];
  build   = { pkgs, lib, fetchNpm, src, meta, passthru, ... }: drv;   # full escape hatch
  meta    = { platforms = lib.platforms.linux; };                      # merged into drv.meta
}
```

`buildPiExtension` picks the shape:

- **simple** — `pname`/`version`/`hash` → unpack the tarball.
- **vendored** — add `vendor = [ … ]` to drop extra tarballs into
  `node_modules/<dir>` (for packages that ship without a lockfile).
- **bespoke** — set `build` to a function returning the derivation. Use
  for `buildNpmPackage` + lockfile installs, `substituteInPlace`
  hotfixes, or local (non-npm) extensions. It receives `fetchNpm`
  (a `{pname;version;hash;}: tarball` helper) and `src` (the main
  tarball, lazy — leave `hash = ""` if unused).

## Procedure: add an npm-published extension

### 1. Fetch metadata

```bash
PKG='@scope/pkg-name'
curl -s "https://registry.npmjs.org/$PKG" \
  | jq -r '.["dist-tags"].latest as $v
           | "version: \($v)\nhash:    \(.versions[$v].dist.integrity)\ndeps:    \(.versions[$v].dependencies)\npi:      \(.versions[$v].pi)"'
```

- **`pi`** — confirm a `pi` manifest exists, else it isn't a pi extension.
- **`deps`** — `null` → simple spec. Deps present → either `vendor` the
  few runtime ones by hand, or use a `build` with `buildNpmPackage`
  (fetch the upstream `package-lock.json` via `pkgs.fetchurl` from
  `raw.githubusercontent.com/.../v<version>/package-lock.json`).

### 2. Security audit (mandatory)

Quick supply-chain review before packaging: open the repo from the npm
`repository`/`homepage` fields (no source link = red flag, ask first);
check reputation/maintenance (license, recent commits, stars, original
vs fork); scan for risk (`rg` for `child_process`, `exec`, `spawn`,
`eval`, `fetch`, `writeFile`, `process.env`, `token`, `secret`,
lifecycle scripts `preinstall`/`install`/`postinstall`). Summarize in
the final response; **stop and ask** on material risk.

### 3. Add the spec file

Create `modules/ai/extensions/<name>.nix`:

```nix
{ ... }:
{
  # <pname> — one-line description.
  # <homepage>
  pi.extensions.<name> = {
    pname = "@scope/pkg-name";
    version = "1.2.3";
    hash = "sha512-…";   # dist.integrity from step 1
  };
}
```

The attr name (`<name>`) is what variant lists and `legacyPackages`
reference. Add `meta.platforms = lib.platforms.linux;` for WSL/Linux-only
extensions (and take `{ lib, ... }`).

### 4. Activate it on a variant

Add the name to `desktopExtensions` and/or `wslExtensions` in
`modules/ai/pi.nix`. `wslExtensions` already includes all of
`desktopExtensions`, so desktop-list entries reach both. An extension
declared but not listed is built only via `legacyPackages` (handy for
work-only extensions a host opts into later).

### 5. Format and verify

```bash
git add -N modules/ai/extensions/<name>.nix        # nix only sees tracked files
nix fmt
# build just the extension (fast; proves hash + unpack):
nix build --no-link .#legacyPackages.x86_64-linux.piExtensions.<name>
# or build the wrapper that carries it:
nix build --no-link .#pi-wsl      # or .#pi-desktop
```

Inspect the unpacked layout carries a `pi` manifest:

```bash
ext=$(nix build --no-link --print-out-paths .#legacyPackages.x86_64-linux.piExtensions.<name>)
jq '{name, version, pi}' "$ext/package.json"
```

## Extensions with npm deps (lockfile install)

When a package has real runtime deps and ships (or has on GitHub) a
`package-lock.json`, use a `build` with `buildNpmPackage`. See
`modules/ai/extensions/pi-azure-devops.nix` and `pi-web-access.nix` for
the full pattern: fetch the lock with `pkgs.fetchurl`, `postPatch` it
into place, `dontNpmBuild`/`dontNpmCheck`, and a custom `installPhase`
that copies the package dir (pi loads `.ts` via jiti). Get `npmDepsHash`
by building once with `lib.fakeHash` and copying the "got:" value.

For a package with one or two deps and **no** lockfile, prefer `vendor`
(see `rpiv-todo.nix`, `pi-interview.nix`).

## Local / in-tree extensions (not on npm)

1. Put sources under `modules/ai/extensions/_local/<name>/` with a
   `package.json` (`pi` manifest), `src/`, and a `default.nix` that
   `runCommand`s the filtered fileset into a pi-package layout (set
   `passthru.piExtension = true`).
2. Add a spec whose `build` callPackages it:

   ```nix
   pi.extensions.<name> = {
     pname = "<name>";
     version = "0.1.0";
     build = { pkgs, ... }: pkgs.callPackage ./_local/<name> { };
   };
   ```

See `agent-browser-edge-bridge.nix` + `_local/agent-browser-edge-bridge/`.

## The wrappers and host wiring

- `modules/ai/pi.nix` defines two first-class wrappers via a shared
  inline module: `flake.wrappers.pi-desktop` and `flake.wrappers.pi-wsl`
  (auto-exposed as `.#pi-desktop` / `.#pi-wsl`). Each uses the wrap-time
  nixpkgs `pkgs.pi-coding-agent`, adds a `runtimePkgs` CLI baseline,
  appends `modules/ai/AGENTS.md`, and builds its extension set into
  `--extension` flags.
- **Install gating is strict "ai AND <platform>"**: `modules/ai/pi.nix`
  declares `pi.enable` in the always-imported `base` HM bucket; the `ai`
  bucket sets `pi.enable = true`; the `desktop-core` bucket installs
  `pi-desktop` and the `wsl` bucket installs `pi-wsl`, both guarded by
  `lib.mkIf config.pi.enable`. So a host gets pi-desktop only with
  ai+desktop, pi-wsl only with ai+wsl.

## Updating or removing an extension

- **Bump:** re-run step 1, update `version` + `hash` in the spec file,
  rebuild.
- **Remove:** delete `modules/ai/extensions/<name>.nix` and remove the
  name from the variant lists in `modules/ai/pi.nix`. Rebuild.

## Validate

```bash
nix build --no-link .#pi-desktop .#pi-wsl
nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath
```
