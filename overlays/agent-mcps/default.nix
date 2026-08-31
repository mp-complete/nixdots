# Overlay: pkgs.agenticMcps — declarative MCP server "packages".
#
# Each entry is an attrset matching the home-manager mcpServerType option shape.
# Use mkLocalMcp for stdio servers and mkRemoteMcp for SSE/HTTP servers.
# Set `package` on local servers to auto-inject their binary into Copilot CLI's PATH.
final: prev:
let
  aiLib = import ../../modules/home/ai/lib.nix {
    lib = final.lib;
    pkgs = final;
  };
in
{
  agenticMcps = {
    # Alexandria — local semantic code-search MCP server.
    # Requires programs.alexandria.enable in home-manager (provides alex on PATH).
    # https://github.com/milespossing/alexandria
    alexandria = aiLib.mkLocalMcp {
      command = [
        "alex"
        "serve"
      ];
    };

    # Work IQ — Microsoft 365 data via M365 Copilot Chat API.
    # Requires M365 Copilot license and tenant admin consent.
    # https://github.com/microsoft/work-iq
    workiq = aiLib.mkLocalMcp {
      command = [
        "npx"
        "-y"
        "@microsoft/workiq@latest"
        "mcp"
      ];
      package = final.nodejs;
    };

    # ICM — Incident management MCP server (Azure HTTP endpoint).
    # Auth token is fetched at runtime via az cli command substitution.
    icm = aiLib.mkRemoteMcp {
      url = "https://icm-mcp-prod.azure-api.net/mcp";
      headers = {
        Authorization = "Bearer $(az account get-access-token --scope api://icmmcpapi-prod/mcp.tools --query accessToken -o tsv)";
      };
    };

    # Azure DevOps — Microsoft's official MCP server.
    # Exposes PR / repo / work-item / pipeline tools and authenticates
    # via the local `az login` session (--authentication azcli), so no
    # PAT is required. Org name is hard-coded to powerbi; change per
    # host if needed.
    # https://github.com/microsoft/azure-devops-mcp
    azureDevops = aiLib.mkLocalMcp {
      command = [
        "npx"
        "-y"
        "@azure-devops/mcp@latest"
        "powerbi"
        "--authentication"
        "azcli"
      ];
      package = final.nodejs;
    };

    # FluentAgent — Microsoft-hosted MCP on the official fluentui.dev
    # domain. Surfaces Fluent UI v9 agent capabilities; tools and
    # prompts are discovered after auth.
    # Auth: OAuth 2.1 + PKCE against Microsoft corp AAD tenant
    # (72f988bf-86f1-41af-91ab-2d7cd011db47), delegated scope
    # `api://3f741cf4-79be-448e-ab12-51bed1ee9ed0/access_as_user`.
    # Requires a Microsoft FTE corp account. The MCP client handles
    # the browser-based sign-in on first connect and refresh after.
    # Playground UI: https://chat.fluentui.dev/
    # Docs (preview):  https://aka.ms/fluent-agent-mcp
    fluentAgent = aiLib.mkRemoteMcp {
      url = "https://chat.fluentui.dev/mcp/server/";
    };
  };
}
