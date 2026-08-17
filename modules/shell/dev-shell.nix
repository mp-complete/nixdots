{ lib, ... }:
let
  inherit (lib) mkOption types;

  devShellModule = {
    options = {
      packages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Packages added to a development shell.";
      };

      runtimeLibraries = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Libraries added to LD_LIBRARY_PATH inside a development shell.";
      };

      env = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Environment variables added to a development shell.";
      };

      shellHook = mkOption {
        type = types.lines;
        default = "";
        description = "POSIX shell initialization contributed to a development shell.";
      };

      fish.interactiveShellInit = mkOption {
        type = types.lines;
        default = "";
        description = "Fish initialization loaded while a development shell is active.";
      };
    };
  };

  mkDevShell =
    pkgs: name: module:
    let
      shellConfig =
        (lib.evalModules {
          class = "devShell";
          modules = [
            devShellModule
            module
          ];
          specialArgs = { inherit pkgs; };
        }).config;

      libraryPathHook = lib.optionalString (shellConfig.runtimeLibraries != [ ]) ''
        export LD_LIBRARY_PATH="${lib.makeLibraryPath shellConfig.runtimeLibraries}:''${LD_LIBRARY_PATH:-}"
      '';

      fishInitScript = pkgs.writeText "${name}-fish-init.fish" shellConfig.fish.interactiveShellInit;
    in
    pkgs.mkShell (
      {
        inherit name;
        packages = shellConfig.packages;
        shellHook = lib.concatLines [
          libraryPathHook
          shellConfig.shellHook
        ];
      }
      // shellConfig.env
      // lib.optionalAttrs (shellConfig.fish.interactiveShellInit != "") {
        NIXDOTS_FISH_INIT = toString fishInitScript;
      }
    );
in
{
  # Development-shell aspects are native dendritic modules in
  # flake.modules.devShell. Profiles compose those modules with `imports` and
  # explicitly expose only final shells through perSystem.devShells.
  _module.args.mkDevShell = mkDevShell;

  flake.modules.homeManager.base = {
    programs.fish.interactiveShellInit = ''
      # Development-shell aspects export Fish initialization scripts through
      # direnv. Load them when the environment changes and on startup when Fish
      # was launched from an already-active development environment.
      function __nixdots_load_dev_shell_fish_init --on-variable NIXDOTS_FISH_INIT
        set -q NIXDOTS_FISH_INIT
        or return

        for script in (string split : -- "$NIXDOTS_FISH_INIT")
          test -r "$script"
          and source "$script"
        end
      end

      __nixdots_load_dev_shell_fish_init
    '';
  };
}
