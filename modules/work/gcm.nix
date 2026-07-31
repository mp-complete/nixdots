{
  flake.modules.homeManager.work =
    { pkgs, lib, ... }:
    {
      # Work repos need Git Credential Manager (OAuth). A real ~/.gitconfig
      # gives `git config --global` a writable destination.
      home.activation.ensureWritableGitconfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        [ -e "$HOME/.gitconfig" ] || touch "$HOME/.gitconfig"
      '';

      home.sessionVariables.GCM_CREDENTIAL_STORE = "gpg";
      programs.git.settings.credential = {
        # Default helper: Git Credential Manager for everything (Azure DevOps, etc).
        # github.com is overridden to use gh in development/git.nix.
        helper = "${pkgs.git-credential-manager}/bin/git-credential-manager";
        useHttpPath = true;
        # The powerbi Azure DevOps org disables PAT creation
        # (DisablePatCreationPolicyViolation). Use the OAuth access token
        # directly instead of exchanging it for a PAT.
        azreposCredentialType = "oauth";
      };

      # PathInstaller-managed tools install to ~/.config/<tool>/CurrentVersion
      shell.initExtra = ''
        for d in "$HOME"/.config/*/CurrentVersion; do
          [ -d "$d" ] && export PATH="$PATH:$d"
        done
      '';
      shell.fishInitExtra = ''
        for d in $HOME/.config/*/CurrentVersion
          test -d $d; and fish_add_path $d
        end
      '';
    };
}
