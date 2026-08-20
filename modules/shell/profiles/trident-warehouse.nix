{ config, mkDevShell, ... }:
{
  flake.modules.devShell.trident-warehouse = {
    imports = with config.flake.modules.devShell; [
      nodejs
      typescript
      yarn
      playwright
    ];

    # Guard for the abbreviations below, mirroring NIXDOTS_YARN_ACTIVE in
    # shell/aspects/yarn.nix. Set by the shell, so it is present exactly while
    # direnv has this profile loaded.
    env.NIXDOTS_TRIDENT_WAREHOUSE_ACTIVE = "1";

    # Abbreviations for this repo's own package scripts. The generic yarn
    # verbs (`ys`, `yi`, `yb`, `yw`, `yib`) live in the yarn aspect; what is
    # left here is the set that only means anything inside TridentWarehouse-UX,
    # so it stays with the profile that knows the repo rather than leaking into
    # every yarn project.
    #
    # Counts from atuin (total / last 45 days):
    #   yarn storybook                                         42 / 2
    #   yarn build:loom                                        41 / 15
    #   yarn workspace @warehouse-ux/extension-app lint --fix  35 / 9
    #   yarn build:extension                                   13 / 4
    #   yarn build:relational-db-ux                            12 / 3
    #   yarn workspace @warehouse-ux/extension-app build       11 / 11
    # Skipped as stale: `yarn test:loom` (0 recent), `yarn build:loom &&
    # yarn build:extension && yarn preview` (0 recent), `yarn build:chat-ui`.
    #
    # Same `--function` guard as the yarn aspect, and for the same reason:
    # `abbr` registrations are per fish *session* and survive direnv unloading
    # the shell, so the guard has to be re-checked at expansion time or `ybl`
    # would keep expanding in unrelated repos.
    fish.interactiveShellInit = ''
      function __nixdots_trident_warehouse_active
        set -q NIXDOTS_TRIDENT_WAREHOUSE_ACTIVE
      end

      function __nixdots_trident_warehouse_abbr_expand
        __nixdots_trident_warehouse_active
        or return 1

        switch $argv[1]
          case yss
            echo 'yarn storybook'
          case ybl
            echo 'yarn build:loom'
          case ybe
            echo 'yarn build:extension'
          case ybr
            echo 'yarn build:relational-db-ux'
          case ylf
            echo 'yarn workspace @warehouse-ux/extension-app lint --fix'
          case ywb
            echo 'yarn workspace @warehouse-ux/extension-app build'
          case '*'
            return 1
        end
      end

      if not set -q __nixdots_trident_warehouse_abbrs_registered
        for __nixdots_trident_warehouse_abbr in yss ybl ybe ybr ylf ywb
          abbr --add $__nixdots_trident_warehouse_abbr \
            --position command \
            --function __nixdots_trident_warehouse_abbr_expand
        end
        set --erase __nixdots_trident_warehouse_abbr

        set --global __nixdots_trident_warehouse_abbrs_registered 1
      end
    '';
  };

  perSystem =
    { pkgs, ... }:
    {
      devShells.trident-warehouse =
        mkDevShell pkgs "trident-warehouse"
          config.flake.modules.devShell.trident-warehouse;
    };

  # worktrunk settings for this repo live in the hand-managed user config at
  # `~/.config/worktrunk/config.toml`, not here — see modules/development/worktrunk.nix.
}
