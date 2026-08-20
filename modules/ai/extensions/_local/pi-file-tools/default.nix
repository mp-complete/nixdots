{
  runCommand,
  lib,
}:
# pi-file-tools — pi extension, built locally (not from npm).
#
# Produces a pi-package directory layout:
#
#   $out/package.json
#   $out/src/index.ts
#
# No test phase: the whole extension is one `session_start` handler calling
# pi's own tool-registry API, so there is nothing to unit-test that would not
# just be a mock of pi itself.
let
  pname = "pi-file-tools";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./src
    ];
  };
in
runCommand "pi-ext-${pname}-${version}"
  {
    inherit src;
    meta = {
      description = "Pi extension: enable pi's built-in find/grep/ls tools.";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
    passthru = {
      inherit pname version;
      piExtension = true;
    };
  }
  ''
    mkdir -p $out
    cp -r $src/. $out/
  ''
