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
      '';
    };
}
