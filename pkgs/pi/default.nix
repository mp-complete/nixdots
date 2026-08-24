# pi, the terminal coding agent, built from lukasl-dev/pi.nix.
#
# The `pi-nix` input carries all the build logic (`coding-agent/package.nix`:
# npm build, the TypeScript patches, and the pre-generated
# `ai/models.generated.ts` + `ai/providers/` that keep the build offline). Only
# the *version-coupled data* is overridden here, because that input's
# `VERSION.json` currently pins v0.84.2 and we want v0.84.3:
#
#   - `src` / `hash`      — the upstream pi tag to build
#   - `package-lock.json` — regenerated for that tag (see below)
#   - `npmDepsHash`       — the FOD hash of the npm cache for that lock
#   - `ai/`               — the pre-generated model catalog for that tag
#
# pi.nix does not build from upstream's own lockfile; its `sync-upstream` app
# runs `npm-lockfile-fix` + `npm audit fix --package-lock-only` first, and
# `coding-agent/package.nix` copies the result — plus `ai/` — over the source
# tree in `postPatch`. Those copies are paths relative to the flake tree, so
# the only way to swap them is to build against a patched *copy* of the input
# — `piNixSrc` below — rather than the input itself.
#
# `ai/` is not optional: it is generated from models.dev by upstream's
# `generate-models` script (vendored so the build stays offline), and it is
# coupled to the source tag. v0.84.2's copy has xai under
# `openai-completions`, while v0.84.3's `providers/xai.ts` returns
# `Provider<"openai-responses">` — building the new tag against the old data
# fails typechecking in packages/ai.
#
# To move to another pi release, mirror pi.nix's sync-upstream and
# regenerate-models apps:
#
#   nix store prefetch-file --json --unpack \
#     https://github.com/earendil-works/pi/archive/refs/tags/vX.Y.Z.tar.gz   # -> hash
#   # in an unpacked, writable copy of that source:
#   npm-lockfile-fix package-lock.json
#   npm audit fix --package-lock-only --ignore-scripts
#   prefetch-npm-deps package-lock.json                                      # -> npmDepsHash
#   npm ci --ignore-scripts
#   npm run generate-models --workspace=packages/ai                          # needs network
#   cp package-lock.json                     <this dir>/package-lock.json
#   cp packages/ai/src/models.generated.ts   <this dir>/ai/
#   cp packages/ai/src/providers/*.models.ts <this dir>/ai/providers/
#   cp -R packages/ai/src/providers/data     <this dir>/ai/providers/
#
# Once pi.nix's own VERSION.json reaches the version we want, this whole
# derivation can be dropped in favour of
# `inputs.pi-nix.packages.${system}.coding-agent` (which is what pi.cachix.org
# has prebuilt); the overlay in overlays/pi-coding-agent.nix is the only
# consumer.
{
  callPackage,
  fetchFromGitHub,
  runCommand,
  pi-nix,
}:
let
  version = "0.84.3";

  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    rev = "v${version}";
    hash = "sha256-fC9pKgP2qD61ae5d7iOqP8anl88J1N1Bq8X8+aAjA2A=";
  };

  # pi.nix's tree with our regenerated lockfile and model catalog in place of
  # its v0.84.2 ones.
  piNixSrc = runCommand "pi.nix-source-pi-${version}" { } ''
    cp -R ${pi-nix} $out
    chmod -R u+w $out
    cp ${./package-lock.json} $out/package-lock.json
    rm -rf $out/ai
    cp -R ${./ai} $out/ai
  '';
in
callPackage "${piNixSrc}/coding-agent/package.nix" {
  inherit src version;
  npmDepsHash = "sha256-cDx28+c4bwtQpiy5+BCvZhZezoZb4WRqfZj2eoEeMbw=";
}
