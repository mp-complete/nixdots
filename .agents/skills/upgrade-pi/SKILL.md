---
name: upgrade-pi
description: Pin pi-coding-agent to a newer upstream release in this nixos flake. Invoke explicitly with /skill:upgrade-pi.
disable-model-invocation: true
metadata:
  author: miles
  repo: ~/.config/nixos
  version: "1.0"
---

# Upgrade pi-coding-agent ahead of nixpkgs

This repo normally uses nixpkgs `pi-coding-agent` directly. Add a temporary
`overlays/pi-coding-agent.nix` only when the user requests an upstream release
newer than nixpkgs. The overlay reuses the nixpkgs build expression, so every
version-coupled source and hash in that expression must be overridden.

The target version comes from the user (e.g. "upgrade pi to 0.84.0").

## Procedure

### 1. Get the source hash

```bash
V=0.79.4   # the requested version
nix-prefetch-url --unpack \
  "https://github.com/earendil-works/pi/archive/refs/tags/v$V.tar.gz" \
  | tail -1 | (read h; nix hash convert --hash-algo sha256 "$h")
```

### 2. Update the overlay

Create or edit `overlays/pi-coding-agent.nix`: set `version`, the source
`hash` (from step 1), and reset the `npmDeps` `outputHash` to a fake
placeholder so the build reports the real one:

```nix
outputHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
```

First inspect the current nixpkgs package expression via
`pkgs.pi-coding-agent.meta.position`. Override any additional version-coupled
fetches it defines. For example, current nixpkgs has a `modelData` npm tarball
whose URL and hash must match the requested version; failing to override it
causes a tarball hash mismatch or extracts the wrong release layout.

If the overlay doesn't exist yet, create it overriding
`prev.pi-coding-agent`, then use it in both consumers:

- `modules/ai/pi.nix`: set the wrapper package to
  `(pkgs.extend piOverlay).pi-coding-agent`.
- `modules/flake/packages.nix`: add the overlay to the local nixpkgs import so
  `pi-upstream` exposes the same version.

### 3. Get the npmDeps hash from the build

New files must be `git add`ed or Nix can't see them (flake = git tree).

```bash
git add overlays/pi-coding-agent.nix
nix build --no-link .#pi-wsl 2>&1 | tail -20
```

Copy the `got:` hash from the "hash mismatch in fixed-output derivation"
error into the overlay's `outputHash`, replacing the placeholder.

### 4. Verify

```bash
nix fmt overlays/pi-coding-agent.nix modules/ai/pi.nix modules/flake/packages.nix
nix build --no-link .#pi-wsl
nix eval --raw .#packages.x86_64-linux.pi-upstream.version
```

The version eval must print the requested version.

## Notes

- Once nixos-unstable ships this version, delete the overlay and restore both
  consumers to direct `pkgs.pi-coding-agent` use.
- Never assume only `src` and `npmDeps` change; re-check the current nixpkgs
  expression for new version-coupled fetches on every bump.
