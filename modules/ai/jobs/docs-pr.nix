# Worked example: the nightly documentation-drift PR.
#
# Disabled by default — flip `enable` (and provision the forge token) on a host
# that has opted into the `pi-agent` bucket. Everything here is ordinary job
# data merged into the same bucket as modules/ai/pi-agent.nix.
{
  flake.modules.nixos.pi-agent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      job = config.piAgent.jobs.nixdots-docs;
    in
    {
      # Prompt hygiene every unattended job gets: an agent with no human in the
      # loop needs explicit stop conditions far more than an interactive one.
      piAgent.defaults = {
        timeout = "45m";
        packages = with pkgs; [
          git
          openssh
          nix
        ];
        excludeTools = [
          "ask_question"
          "ask_user_question"
          "interview"
        ];
        appendSystemPrompt = ''
          You are running unattended on a schedule. No human will answer you.

          - Never ask questions or wait for input; if you are blocked, report why and stop.
          - Never push to a default branch (main/master) and never force-push.
          - Never amend, rebase, or rewrite existing commits.
          - If the task already appears to be done, exit without making changes.
          - Prefer doing nothing over doing something you are unsure about.
        '';
      };

      piAgent.jobs.nixdots-docs = {
        enable = false; # bootstrap `pi-agent-login` first, then flip this

        description = "Nightly documentation drift check on nixdots";
        schedule = "*-*-* 02:30:00";

        repo = {
          url = "https://git.opencurry.xyz/miles/nixdots.git";
          ref = "main";
        };

        # Own repo, so its .agents/skills and .pi settings are safe to load.
        approveProject = true;

        packages = [ pkgs.tea ]; # Forgejo CLI, for opening the PR

        tools = [
          "read"
          "grep"
          "find"
          "ls"
          "edit"
          "write"
          "bash"
        ];

        # Forge credential. Put a Forgejo access token under the
        # `pi-agent-forge-token` key in secrets/general.yaml, then this template
        # lands it in the unit environment as GITEA_TOKEN.
        environmentFile = lib.mkIf job.enable config.sops.templates."pi-agent-forge.env".path;

        prompt = ''
          You are running unattended on a fresh clone of main.

          1. Compare docs/ and every AGENTS.md / README.md against the current code.
          2. If nothing has drifted, print "NO CHANGES" and stop. Do not open a PR.
          3. Otherwise: create branch bot/docs-<date>, commit ONLY documentation
             changes, push it, and open a PR with `tea pr create`.
          4. Never modify .nix files, never touch main, never force-push.
        '';
      };

      # Only declare the secret when the job is on, so a host can import the
      # bucket without owning that key.
      sops = lib.mkIf job.enable {
        secrets.pi-agent-forge-token.sopsFile = ../../../secrets/general.yaml;
        templates."pi-agent-forge.env".content = ''
          GITEA_TOKEN=${config.sops.placeholder.pi-agent-forge-token}
        '';
      };
    };
}
