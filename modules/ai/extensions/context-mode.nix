{ lib, ... }:
{
  # context-mode — context window optimization, session memory, and MCP
  # tool bridge for the pi coding agent.
  # https://github.com/mksglu/context-mode
  pi.extensions.context-mode = {
    pname = "context-mode";
    version = "1.0.169";
    hash = "sha512-94JIaFuLjF9SO2BsGTrbGtyT44K95+9OC8BdbaL/UT76xOkanJLfUR5CzmNw+GELXZQqH4nBrKg9wjBnSFkVnQ==";
    meta = {
      description = "Pi coding agent extension: context window optimization, session memory, and MCP tool bridge";
      homepage = "https://github.com/mksglu/context-mode";
      license = lib.licenses.elastic20;
      platforms = lib.platforms.linux;
    };

    build =
      {
        pkgs,
        src,
        meta,
        passthru,
        ...
      }:
      pkgs.buildNpmPackage {
        inherit (passthru) pname version;
        inherit src meta passthru;
        npmDepsHash = "sha256-+cdlrKEO/GHnwoMWTrwhVgbc3OkW+CCGCa2ppHCMHvk=";

        postPatch = ''
          cp ${./context-mode-package-lock.json} package-lock.json
        '';

        # The published tarball already ships the built bundles and the pi
        # adapter. Native lifecycle scripts are unnecessary: context-mode
        # prefers the Node >= 22.5 built-in node:sqlite, so better-sqlite3's
        # postinstall (which downloads/compiles a native binding) can be
        # skipped safely in this wrapper environment.
        npmInstallFlags = [
          "--ignore-scripts"
          "--omit=dev"
          "--omit=peer"
        ];

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
