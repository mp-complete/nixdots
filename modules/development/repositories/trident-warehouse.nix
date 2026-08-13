{
  repo.shells.trident-warehouse = {
    directories = [ "TridentWarehouse-UX" ];
    aspects = [
      "nodejs"
      "typescript"
      "yarn"
      "playwright"
    ];
  };

  flake.wrappers.worktrunk.settings.projects."dev.azure.com/powerbi/Trident/_git/TridentWarehouse-UX" = {
    worktree-path = "{{ repo_path }}/../{{ branch | sanitize }}";
    post-start = "yarn install && yarn build";
  };
}
