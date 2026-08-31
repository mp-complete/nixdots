{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;

  mcpServerType = types.submodule {
    options = {
      type = mkOption {
        type = types.enum [
          "local"
          "remote"
        ];
        description = "MCP server connection type.";
      };
      command = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Command and arguments for local MCP servers.";
      };
      url = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "URL for remote MCP servers.";
      };
      enabled = mkOption {
        type = types.bool;
        default = true;
        description = "Whether this MCP server is enabled.";
      };
      environment = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Environment variables for local MCP servers.";
      };
      headers = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Headers for remote MCP servers.";
      };
      package = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = "Optional package providing the MCP server binary. Auto-added to Copilot CLI's wrapper PATH.";
      };
    };
  };

in
{
  options.my.ai = {
    copilot-cli = {
      enable = mkEnableOption "GitHub Copilot CLI";
      hooks = mkOption {
        type = types.attrsOf (types.listOf (types.attrsOf types.anything));
        default = { };
        description = ''
          Copilot CLI hooks keyed by event name (sessionStart, sessionEnd,
          userPromptSubmitted, preToolUse, postToolUse, errorOccurred).
          Each event maps to a list of hook objects ({ type, bash, timeoutSec, … }).
          Merged into ~/.copilot/config.json on activation.
        '';
        example = {
          sessionEnd = [
            {
              type = "command";
              bash = "notify-send 'Done'";
              timeoutSec = 5;
            }
          ];
        };
      };
      notifications = {
        enable = mkEnableOption "desktop notifications via Copilot CLI hooks (notify-send)";
      };
    };

    mcp.servers = mkOption {
      type = types.attrsOf mcpServerType;
      default = { };
      description = "MCP servers written to Copilot CLI's mcp-config.json.";
    };
  };
}
