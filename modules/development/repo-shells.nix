{ config, lib, ... }:
let
  inherit (lib) mkOption types;

  aspectModule = {
    options = {
      packages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Packages added to a repository development shell.";
      };

      runtimeLibraries = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Libraries added to LD_LIBRARY_PATH inside the repository shell.";
      };

      env = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Environment variables added to a repository development shell.";
      };

      shellHook = mkOption {
        type = types.lines;
        default = "";
        description = "POSIX shell initialization contributed by a repository aspect.";
      };

      fish.interactiveShellInit = mkOption {
        type = types.lines;
        default = "";
        description = "Fish initialization loaded while this repository environment is active.";
      };
    };
  };

  shellType = types.submodule (
    { name, ... }:
    {
      options = {
        aspects = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Names of repository aspects to merge into this development shell.";
        };

        directories = mkOption {
          type = types.listOf types.str;
          default = [ name ];
          description = "Directory basenames that `use nixdots` maps to this development shell.";
        };
      };
    }
  );

  evalShell =
    pkgs: name: shell:
    let
      selectedAspects = map (
        aspectName:
        config.repo.aspects.${aspectName}
          or (throw "repo shell '${name}' references unknown aspect '${aspectName}'")
      ) shell.aspects;

      aspectConfig =
        (lib.evalModules {
          modules = [ aspectModule ] ++ selectedAspects;
          specialArgs = { inherit pkgs; };
        }).config;

      libraryPathHook = lib.optionalString (aspectConfig.runtimeLibraries != [ ]) ''
        export LD_LIBRARY_PATH="${lib.makeLibraryPath aspectConfig.runtimeLibraries}:''${LD_LIBRARY_PATH:-}"
      '';

      fishInitScript = pkgs.writeText "${name}-fish-init.fish" aspectConfig.fish.interactiveShellInit;
      environment =
        aspectConfig.env
        // {
          NIXDOTS_REPO_ASPECTS = lib.concatStringsSep ":" shell.aspects;
        }
        // lib.optionalAttrs (aspectConfig.fish.interactiveShellInit != "") {
          NIXDOTS_FISH_INIT = toString fishInitScript;
        };
    in
    pkgs.mkShell (
      {
        inherit name;
        packages = aspectConfig.packages;
        shellHook = lib.concatLines [
          libraryPathHook
          aspectConfig.shellHook
        ];
      }
      // environment
    );
in
{
  options.repo = {
    aspects = mkOption {
      type = types.attrsOf types.deferredModule;
      default = { };
      description = "Reusable modules that contribute packages and shell behavior to repository environments.";
    };

    shells = mkOption {
      type = types.attrsOf shellType;
      default = { };
      description = "Named development shells assembled from repository aspects.";
    };
  };

  config = {
    perSystem =
      { pkgs, ... }:
      {
        devShells = lib.mapAttrs (evalShell pkgs) config.repo.shells;
      };

    flake.modules.homeManager.base = lib.mkIf (config.repo.shells != { }) {
      programs.fish.interactiveShellInit = ''
        # Repository aspects export Fish initialization scripts through
        # direnv. Load them when the environment changes and on startup when
        # Fish was launched from an already-active repository environment.
        function __nixdots_load_repo_fish_init --on-variable NIXDOTS_FISH_INIT
          set -q NIXDOTS_FISH_INIT
          or return

          for script in (string split : -- "$NIXDOTS_FISH_INIT")
            test -r "$script"
            and source "$script"
          end
        end

        __nixdots_load_repo_fish_init
      '';
    };
  };
}
