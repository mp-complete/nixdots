{
  flake.modules.devShell.yarn =
    { pkgs, ... }:
    {
      packages = [ pkgs.yarn ];
      env.NIXDOTS_YARN_ACTIVE = "1";

      fish.interactiveShellInit = ''
        # Fish's bundled Yarn 1 completion knows the `workspace` command but
        # does not complete workspace names, unlike Yarn's Bash completion.
        function __nixdots_yarn_aspect_active
          set -q NIXDOTS_YARN_ACTIVE
        end

        function __nixdots_yarn_workspace_names
          command yarn --silent workspaces info 2>/dev/null |
            string match --regex --groups-only '^  "([^"]+)": \{$'
        end

        function __nixdots_yarn_needs_workspace
          __nixdots_yarn_aspect_active
          or return 1

          set --local tokens (commandline --tokens-expanded --cut-at-cursor)
          set --local workspace_index (contains --index -- workspace $tokens)

          test -n "$workspace_index"
          and test (count $tokens) -eq $workspace_index
        end

        if not set -q __nixdots_yarn_completion_registered
          complete \
            --command yarn \
            --no-files \
            --condition __nixdots_yarn_needs_workspace \
            --arguments '(__nixdots_yarn_workspace_names)' \
            --description 'Yarn workspace'

          set --global __nixdots_yarn_completion_registered 1
        end

        # Abbreviations for the yarn invocations typed verbatim, everywhere
        # yarn is used. From atuin: `yarn start` 130, `yarn install` 92,
        # `yarn build` 41, `yarn workspace ...` 80 (which the completion above
        # then finishes), `yarn install && yarn build` 16.
        #
        # `abbr` is per *session*, not per directory, and nothing erases these
        # when direnv unloads the shell -- so a plain `abbr -a ys 'yarn start'`
        # would keep expanding in unrelated directories for the rest of the
        # session. `--function` avoids that: fish leaves the token untouched
        # when the function exits non-zero, so the guard below re-checks
        # NIXDOTS_YARN_ACTIVE at *expansion* time rather than at registration.
        function __nixdots_yarn_abbr_expand
          __nixdots_yarn_aspect_active
          or return 1

          switch $argv[1]
            case ys
              echo 'yarn start'
            case yi
              echo 'yarn install'
            case yb
              echo 'yarn build'
            case yw
              echo 'yarn workspace'
            case yib
              echo 'yarn install && yarn build'
            case '*'
              return 1
          end
        end

        if not set -q __nixdots_yarn_abbrs_registered
          for __nixdots_yarn_abbr in ys yi yb yw yib
            abbr --add $__nixdots_yarn_abbr \
              --position command \
              --function __nixdots_yarn_abbr_expand
          end
          set --erase __nixdots_yarn_abbr

          set --global __nixdots_yarn_abbrs_registered 1
        end
      '';
    };
}
