{ config, mkDevShell, ... }:
{
  flake.modules.devShell.trident-warehouse = {
    imports = with config.flake.modules.devShell; [
      nodejs
      typescript
      yarn
      playwright
    ];
  };

  perSystem =
    { pkgs, ... }:
    {
      devShells.trident-warehouse =
        mkDevShell pkgs "trident-warehouse"
          config.flake.modules.devShell.trident-warehouse;
    };

  flake.wrappers.worktrunk.settings.projects."dev.azure.com/powerbi/Trident/_git/TridentWarehouse-UX" =
    {
      worktree-path = "{{ repo_path }}/../{{ branch | sanitize }}";
      post-start = "yarn install && yarn build";
    };
}
