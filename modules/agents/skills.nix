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

      # Matt Pocock's starter workflow. The user-facing entry points are
      # grill-me, grill-with-docs, wayfinder, and diagnosing-bugs; the rest
      # are their required supporting skills.
      mattPocockSkills = [
        "engineering/diagnosing-bugs"
        "engineering/domain-modeling"
        "engineering/grill-with-docs"
        "engineering/prototype"
        "engineering/research"
        "engineering/setup-matt-pocock-skills"
        "engineering/wayfinder"
        "productivity/grill-me"
        "productivity/grilling"
      ];

      # Opt-in local skills, enabled via `skills.extra = [ "figma-to-spec" ];`.
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
          sources = {
            nixdots.path = ./_skills;
            matt-pocock = {
              input = "matt-pocock-skills";
              subdir = "skills";
            };
          };
          skills.enable = builtinSkills ++ mattPocockSkills ++ config.skills.extra;
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
