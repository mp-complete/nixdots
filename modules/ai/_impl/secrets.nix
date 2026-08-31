{
  inputs,
  config,
  lib,
  ...
}:
let
  cfg = config.my.ai;
  sopsFile = ./api-keys.enc.yaml;

  # Keep in sync with api-keys.enc.yaml
  keys = [
    "github"
  ];
in
{
  imports = [
    inputs.sops-nix.homeManagerModules.sops
  ];

  config = lib.mkIf cfg.copilot-cli.enable {
    sops = {
      age.keyFile = lib.mkDefault "${config.home.homeDirectory}/.config/sops/age/keys.txt";

      secrets = lib.genAttrs keys (key: {
        inherit sopsFile;
      });

      templates."ai-env".content = "export COPILOT_GITHUB_TOKEN=${config.sops.placeholder.github}";
    };
  };
}
