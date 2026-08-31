{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.ai;
  cop = cfg.copilot-cli;

  # Serialize a shared MCP server to Copilot CLI's format.
  # Copilot uses separate command and args fields for local MCP servers.
  serializeMcp =
    _name: srv:
    let
      base = lib.optionalAttrs (srv.type == "local") {
        type = "local";
        command = builtins.head srv.command;
        args = builtins.tail srv.command;
        tools = [ "*" ];
      };
      remote = lib.optionalAttrs (srv.type == "remote" && srv.url != null) {
        type = "http";
        url = srv.url;
        tools = [ "*" ];
      };
      env = lib.optionalAttrs (srv.environment != { }) {
        env = srv.environment;
      };
      hdrs = lib.optionalAttrs (srv.headers != { }) {
        headers = srv.headers;
      };
    in
    base // remote // env // hdrs;

  enabledMcpServers = lib.filterAttrs (_: srv: srv.enabled) cfg.mcp.servers;
  mcpJson = lib.mapAttrs serializeMcp enabledMcpServers;
  mcpConfigJson = builtins.toJSON { mcpServers = mcpJson; };

  # Collect MCP server packages for PATH injection
  mcpPackages = lib.filter (p: p != null) (
    lib.mapAttrsToList (_: srv: srv.package) enabledMcpServers
  );

  # Default notification hooks using notify-send
  notifyHooks = lib.optionalAttrs cop.notifications.enable {
    sessionEnd = [
      {
        type = "command";
        bash = ''
          INPUT=$(cat)
          REASON=$(echo "$INPUT" | ${lib.getExe pkgs.jq} -r '.reason')
          case "$REASON" in
            complete)
              ${lib.getExe pkgs.libnotify} --app-name "Copilot" --urgency normal --icon dialog-positive \
                "Task Complete" "Copilot finished working." ;;
            error)
              ${lib.getExe pkgs.libnotify} --app-name "Copilot" --urgency critical --icon dialog-error \
                "Session Error" "Copilot session ended with an error." ;;
            abort|timeout)
              ${lib.getExe pkgs.libnotify} --app-name "Copilot" --urgency normal --icon dialog-warning \
                "Session Ended" "Copilot session was ''${REASON}." ;;
            user_exit)
              ${lib.getExe pkgs.libnotify} --app-name "Copilot" --urgency low --icon dialog-information \
                "Session Closed" "Copilot session ended." ;;
          esac
        '';
        timeoutSec = 5;
      }
    ];
    errorOccurred = [
      {
        type = "command";
        bash = ''
          INPUT=$(cat)
          MSG=$(echo "$INPUT" | ${lib.getExe pkgs.jq} -r '.error.message // "Unknown error"')
          ${lib.getExe pkgs.libnotify} --app-name "Copilot" --urgency critical --icon dialog-error \
            "Error" "$MSG"
        '';
        timeoutSec = 5;
      }
    ];
  };

  # Merge notification hooks with user-defined hooks (user hooks take precedence)
  allHooks = lib.recursiveUpdate notifyHooks cop.hooks;

  # Nix-managed config overlay merged into ~/.copilot/config.json at launch.
  # Only the "hooks" key is managed; auth/model/tokens remain mutable.
  hooksOverlay = pkgs.writeText "copilot-hooks-overlay.json" (builtins.toJSON { hooks = allHooks; });

  mergeHooksScript = pkgs.writeShellScript "copilot-merge-hooks" ''
    COPILOT_CFG="$HOME/.copilot/config.json"
    if [ -f "$COPILOT_CFG" ]; then
      ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "$COPILOT_CFG" ${hooksOverlay} > "$COPILOT_CFG.tmp" \
        && mv "$COPILOT_CFG.tmp" "$COPILOT_CFG"
    else
      mkdir -p "$HOME/.copilot"
      cp ${hooksOverlay} "$COPILOT_CFG"
    fi
  '';

  hooksRun = lib.optionalString (allHooks != { }) "--run ${mergeHooksScript}";

  copilot-wrapped = pkgs.symlinkJoin {
    name = "copilot-wrapped";
    paths = [ pkgs.github-copilot-cli ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild =
      let
        secretsRun = ''
          --run '[ -f "${config.sops.templates."ai-env".path}" ] && . "${
            config.sops.templates."ai-env".path
          }"'
        '';
        pathPrefix = lib.optionalString (
          mcpPackages != [ ]
        ) "--prefix PATH : ${lib.makeBinPath mcpPackages}";
      in
      ''
        wrapProgram $out/bin/copilot \
          ${pathPrefix} \
          ${hooksRun} \
          ${secretsRun}
      '';
  };
in
{
  config = lib.mkIf cop.enable {
    home.packages = [
      copilot-wrapped
    ];

    home.file = lib.mkIf (enabledMcpServers != { }) {
      ".copilot/mcp-config.json".text = mcpConfigJson;
    };
  };
}
