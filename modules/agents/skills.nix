{ inputs, ... }:
{
  flake.modules.homeManager.skills =
    { config, lib, ... }:
    let
      # Always-on skills deployed to every host that imports this bucket.
      builtinSkills = [
        "writing-skills"
        "warehouse-ux-pr-review"
        "html-report"
        "ado-pr-markdown"
        "context-reflect"
      ];

      # Opt-in skills, enabled via `skills.extra = [ "figma-to-spec" ];`.
      availableSkills = [
        "figma-to-spec"
        "fluent-ui-v9"
      ];
    in
    {
      imports = [ inputs.agent-skills.homeManagerModules.default ];

      options.skills.extra = lib.mkOption {
        type = lib.types.listOf (lib.types.enum availableSkills);
        default = [ ];
        description = "Optional skills to deploy in addition to the built-ins.";
      };

      config = {
        programs.agent-skills = {
          enable = true;
          sources.nixdots.path = ./_skills;
          skills.enable = builtinSkills ++ config.skills.extra;
          targets.agents = {
            enable = true;
            structure = "link";
            dest = ".agents/skills";
          };
        };

        home.sessionVariables.AGENTS_SKILLS_DIR = "${config.home.homeDirectory}/.agents/skills";
      };
    };
}
