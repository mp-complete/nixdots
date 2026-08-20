{
  runCommand,
  lib,
  nodejs,
}:
# pi-scan-guard — pi extension, built locally (not from npm).
#
# Produces a pi-package directory layout:
#
#   $out/package.json
#   $out/src/index.ts      (the tool_call hook)
#   $out/src/detect.mjs    (pure detection logic, unit-tested)
#   $out/test/*.test.mjs
#
# The detection logic is plain ESM rather than TypeScript so the check phase
# can run it under `node --test` without a TS loader; pi loads `index.ts`
# through jiti and imports the .mjs sibling normally.
let
  pname = "pi-scan-guard";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./src
      ./test
    ];
  };
in
runCommand "pi-ext-${pname}-${version}"
  {
    inherit src;
    nativeBuildInputs = [ nodejs ];
    meta = {
      description = "Pi extension: block unbounded filesystem scans before they run.";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
    passthru = {
      inherit pname version;
      piExtension = true;
    };
  }
  ''
    cd $src
    node --test 'test/*.test.mjs'

    mkdir -p $out
    cp -r $src/. $out/
  ''
