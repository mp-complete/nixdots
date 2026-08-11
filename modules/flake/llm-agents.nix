{ inputs, ... }:
let
  overlays = [
    inputs.llm-agents.overlays.shared-nixpkgs

    # Temporary: hold pi at 0.83.0 (see overlays/pi-pin.nix).
    (import ../../overlays/pi-pin.nix { inherit (inputs) llm-agents-pinned; })

    # Bun 1.3.13 standalone executables produced by `bun build --compile`
    # currently segfault on NixOS/WSL. Pi supports a Node-based build; Hunk
    # needs Bun, so bundle its JavaScript and run it with the working Bun
    # runtime instead of embedding Bun in a standalone executable.
    (final: prev: {
      llm-agents = prev.llm-agents // {
        pi = prev.llm-agents.pi.override { useBun = false; };

        hunk =
          if final.stdenv.hostPlatform.system == "x86_64-linux" then
            prev.llm-agents.hunk.overrideAttrs (old: {
              nativeBuildInputs = old.nativeBuildInputs ++ [ final.makeWrapper ];

              buildPhase = ''
                runHook preBuild
                mkdir -p .bun-tmp .bun-install hunk-dist
                BUN_TMPDIR=$PWD/.bun-tmp \
                BUN_INSTALL=$PWD/.bun-install \
                ${final.bun}/bin/bun build --target bun \
                  --external '@opentui/core-*' \
                  ./src/main.tsx --outdir hunk-dist
                runHook postBuild
              '';

              installPhase = ''
                runHook preInstall
                mkdir -p $out/lib/hunk
                cp -r hunk-dist/* $out/lib/hunk/

                nativeCore=$(find node_modules -path '*/@opentui/core-linux-x64' -print -quit)
                test -n "$nativeCore"
                mkdir -p $out/lib/hunk/node_modules/@opentui
                cp -rL "$nativeCore" $out/lib/hunk/node_modules/@opentui/core-linux-x64

                makeWrapper ${final.bun}/bin/bun $out/bin/hunk \
                  --add-flags $out/lib/hunk/main.js \
                  --set HUNK_INSTALL_SOURCE nix
                cp -r ./skills $out/
                runHook postInstall
              '';
            })
          else
            prev.llm-agents.hunk;
      };
    })
  ];
in
{
  # Use the consumer's nixpkgs for llm-agents packages, including flake-side
  # wrapper outputs such as pi-desktop and pi-wsl.
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        inherit overlays;
      };
    };

  # Hosts use this package set through NixOS and Home Manager's useGlobalPkgs.
  flake.modules.nixos.base.nixpkgs.overlays = overlays;
}
