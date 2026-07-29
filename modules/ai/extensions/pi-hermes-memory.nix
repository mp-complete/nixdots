{ ... }:
{
  # pi-hermes-memory — persistent memory, session search, and secret scanning
  # for Pi, backed by SQLite FTS5.
  # https://github.com/chandra447/pi-hermes-memory
  pi.extensions.pi-hermes-memory = {
    pname = "pi-hermes-memory";
    version = "0.9.1";
    hash = "sha512-ZFRKt1KyjfYhXExNCogH8S8BUWgc2NgjhQkoIeJR1u9X/NEjSNCXiHpu9hfmDFYZf4TxKnulJWcf1JN0pzomtQ==";
    meta = {
      description = "Persistent memory, session search, and secret scanning for Pi";
      homepage = "https://github.com/chandra447/pi-hermes-memory";
    };

    build =
      {
        pkgs,
        src,
        meta,
        passthru,
        ...
      }:
      let
        packageLockSource = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/chandra447/pi-hermes-memory/v0.9.1/package-lock.json";
          hash = "sha256-fiSVbCIxbMGk7zmTQZsUGv4a8wjvmeHaMr0KQU3fz74=";
        };
        # Upstream's lock omits integrity for three nested @earendil-works
        # packages. Add their registry-published SRI values so Nix's strict
        # npm dependency fetcher can verify them.
        packageLock =
          pkgs.runCommand "pi-hermes-memory-package-lock.json" { nativeBuildInputs = [ pkgs.jq ]; }
            ''
              jq '
                .packages["node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-agent-core"].integrity = "sha512-BF9WPhixIFjT6Kp3Iz3H6ugkU+4AWotM8py96XE5pIK0arJbQKMWbR+dXSWWDEmR5yc/aFQODnuyowOEzMGO7Q==" |
                .packages["node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai"].integrity = "sha512-5GNKfdrRJ4uZ5Zd9iudoXggi/BbUcKnD/xfRHtdR+7q4vWqPvfx8auFuaT+ewGBVI8K4wj87eigFQ/iCSuy9RQ==" |
                .packages["node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui"].integrity = "sha512-OvOAMIbXiC9OSse17YMiXIsI9AS5XM/ZV8N/k+UzdlRpPILDQYmLElevgGW92kkXR8qHBClIdzhCjuzlBGvphA=="
              ' ${packageLockSource} > $out
            '';
      in
      pkgs.buildNpmPackage {
        inherit (passthru) pname version;
        inherit src meta passthru;
        npmDepsHash = "sha256-NzIQ+LOpnE1dyGtX3neigB6/JiOI6mTApcZZe+rS0Y0=";

        postPatch = ''
          cp ${packageLock} package-lock.json
        '';

        # The lock includes Pi and TypeScript tooling used only by upstream's
        # source checks. Runtime needs pi-tui and the native better-sqlite3
        # addon; npm builds the latter against the wrapper's Node runtime.
        npmInstallFlags = [ "--omit=dev" ];
        dontNpmBuild = true;
        dontNpmCheck = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r . $out/
          rm -f $out/package-lock.json $out/node_modules/.package-lock.json
          runHook postInstall
        '';
      };
  };
}
