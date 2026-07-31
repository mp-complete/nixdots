# Wrapper architecture, findings & roadmap

Status of the `nix-wrapper-modules` integration in this repo, the decisions
behind it, what got dropped on the way here, and where to go next.

## TL;DR

- Wrappers are defined in the **flake-parts `flake.wrappers` registry**
  (`modules/flake/wrappers.nix`) and consumed **explicitly** via
  `config.flake.wrappers.<n>.wrap { inherit pkgs; }`.
- **There is no wrapper overlay** (we chose "Variant B"): `pkgs.<n>` stays
  vanilla upstream; nothing is shadowed.
- The flake-parts module auto-exposes every wrapper as
  `packages.<system>.<n>` — `nix build/run .#kitty`, `.#pi-wsl`, …
- `nix flake check` builds every host toplevel (`modules/flake/checks.nix`).

## Why Variant B (registry, no overlay)

We evaluated three shapes:

| | Definition | Consumption | `pkgs.<n>` |
|---|---|---|---|
| **A** homegrown overlay aggregator (old) | `wrappers/<t>/default.nix` exporting `{package; overlay;}` | `pkgs.<n>` everywhere | replaced |
| **A′** flake-parts registry → derived overlay | `flake.wrappers.<n>` | `pkgs.<n>` everywhere | replaced |
| **B** flake-parts registry, no overlay (current) | `flake.wrappers.<n>` | `config.flake.wrappers.<n>.wrap {…}` | vanilla |

Variant B's unique payoff over A/A′ is **architectural hygiene**: no global
`pkgs` mutation, explicit dependencies, and the wrap-of-wrap base-recursion
footgun disappears (wrappers build against clean nixpkgs). The cost is that
every consumer references the registry, and cross-references must be threaded
by hand (see below). We accepted that cost on purpose.

## How it fits together

```
modules/flake/wrappers.nix     # imports flakeModules.wrappers; defines flake.wrappers.*;
                               # sets perSystem.wrappers.pkgs
wrappers/<tool>/<tool>.nix     # the wrapper MODULE: { pkgs, wlib, ... }: { imports=[…]; package=…; … }
wrappers/<tool>/module.nix     # reusable option-defining module (hunk, worktrunk, pi)
modules/<area>/<feature>.nix   # consumers: config.flake.wrappers.<n>.wrap { inherit pkgs; }
modules/flake/checks.nix       # flake.checks.<sys>.<host> = host toplevel
modules/flake/packages.nix     # nvim (callPackage) + pi-upstream; everything else is auto-exposed
```

### Patterns in use

- **Base packages from flake inputs** (`hunk`, `worktrunk`): resolved per-system
  via the wrap-time pkgs — `inputs.hunk.packages.${pkgs.stdenv.hostPlatform.system}.default`
  (the wrapper analogue of flake-parts `inputs'`). `inputs` stays in the
  flake-parts layer and is closed over; it never leaks into a submodule arg.
- **Cross-references** (`tmux` → wrapped `yazi`/`worktrunk`): injected via
  `_module.args` from `wrappers.nix`, because the overlay is gone and a wrapper
  module can't see `config.flake`. This is the manual unification Variant B
  trades for.
- **pi variant chain**: composed at the **module level** in `modules/ai/pi.nix` —
  `pi-desktop`/`pi-wsl` share one inline wrapper module (a `mkPi extNames` helper)
  rather than wrapping a base wrapper, so each variant is a single flat wrapper
  (not a wrapper-of-a-wrapper). Each uses the wrap-time nixpkgs
  `pkgs.pi-coding-agent` directly.
- **pi extensions**: declared as pure-data specs in `pi.extensions.<name>`
  (one file per extension under `modules/ai/extensions/`), built lazily by
  `flake.lib.buildPiExtension pkgs spec` at wrap-time — so extensions never
  become `packages.*` outputs. A debug handle lives at
  `legacyPackages.<system>.piExtensions.<name>` (hidden from `nix flake show`).
  See the `pi-extensions` skill.
- **`runtimePkgs` for self-contained wrappers** (`tmux`→`jq`, `waybar`→`blueman`/`pavucontrol`,
  `yazi`→`zellij`/`git`, `pi`→its CLI baseline). These tools are *appended* to the
  wrapper's PATH (a global install still wins), so the wrapper works standalone
  (`nix run .#tmux`) and can't break when a global package moves. This is the
  root-cause fix for the "referenced-but-not-installed" class of bug; prefer it
  over adding a global package whenever a wrapper shells out to a bare command.

### Recipe: add or edit a wrapper

1. Write/adjust `wrappers/<tool>/<tool>.nix` as a module:
   `{ pkgs, wlib, ... }: { imports = [ wlib.wrapperModules.<tool> ]; package = pkgs.<tool>; …config… }`
   (or `imports = [ ./module.nix ]` for a bespoke option set).
2. Register it: add `<tool> = import ../../wrappers/<tool>/<tool>.nix;` to
   `flake.wrappers` in `modules/flake/wrappers.nix`.
3. Consume it in a feature file: `config.flake.wrappers.<tool>.wrap { inherit pkgs; }`
   in `home.packages` / `environment.systemPackages` / `programs.<x>.package`.
4. If it shells out to bare commands, add `runtimePkgs = [ … ];` to the module.
5. `nix build .#<tool>` and `nix eval .#checks.x86_64-linux.<host>.drvPath`.

## Validation

- `nix flake check` — builds all host toplevels (and the wrappers they install).
- `nix build .#<wrapper>` — build one wrapper in isolation.
- `nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`
  — fast "does it evaluate" check without building.

## Findings: features dropped in the dendritic migration

The pre-dendritic `hosts/`, `modules.old.d/`, and `flake.old.nix` were removed
(all git-tracked — recover any of them with `git show HEAD~1:<path>`). Audit of
what the old tree contained vs. the new one:

- **Accounted for**: core/shell, desktop, dev, neovim, network, nh+comma+nix-index
  (`system/nix-tools.nix`), office, rofi/dunst/swaylock/waybar (wrappers), secrets,
  sesh, syncthing, userland (discord/spotify/kitty), virtualization, wallpapers,
  wayland, wine, wm (i3/sway), work, wsl.
- **Intentionally dropped** (desktop stack moved to i3 + sway): `niri` and its
  shells `noctalia`/`dms`; `kde` (Plasma 6 + sddm); `swayidle` (was never wired up
  — there is currently **no idle auto-lock** on laplace; `swaylock` handles manual
  locking only).
- **⚠️ Dropped functional feature, not re-implemented: `openclaw-node`** — an agent
  remote-exec node (exposed `system.run` / `system.which` via an OpenClaw gateway,
  with sops-managed gateway/token secrets and an exec-approvals policy). Only a
  stale comment in `modules/system/users.nix` still mentions "openclaw". If you want
  agent remote-exec back, recover it with
  `git show HEAD~1:modules.old.d/openclaw-node/default.nix` and port it to a
  `modules/<area>/openclaw-node.nix` feature module.

## Roadmap: patterns we're not using yet

Ranked by value to this repo.

1. **More `runtimePkgs` coverage.** Audit remaining wrappers for bare-command
   PATH deps and bundle them. This is the single most underused capability.
2. **`.wrap` at the consumption site** for one-off host tweaks without new
   registry entries, e.g. a host adding one pi extension:
   `config.flake.wrappers.pi-desktop.wrap { inherit pkgs; extensions = [ … ]; }`
   (lists accumulate).
3. **A per-host `pi.extensions` opt-in list** (mirroring `skills.extra`) so a
   host can activate a declared-but-unlisted extension (e.g. a work-only one)
   without editing the shared `desktopExtensions`/`wslExtensions` sets in
   `modules/ai/pi.nix`. *(Done for the desktop/wsl split; per-host extras TBD.)*
4. **`perSystem.wrappers.control_type = "exclude"`** to drop wrappers from the
   built `packages.*` set, keeping `nix flake check` lean.
5. **`aliases`** (symlinkScript option) to expose convenience binary names from a
   wrapper (e.g. worktrunk as `git-wt`).
6. **CI**: wire `nix flake check` into `.github/` now that `flake.checks` exists.

Deliberately **not** pursued: `.install` enable-modules (clash with this repo's
import = enable convention), `drv.postBuild` launcher scripts (niche), bubblewrap
sandboxing (upstream roadmap, not production-ready).
