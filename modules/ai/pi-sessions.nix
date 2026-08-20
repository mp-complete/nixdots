{ ... }:
{
  # A television channel over pi's sessions -- `tv pi-sessions`, or ctrl-t
  # after typing `pi --session`.
  #
  #   Active   live sessions, needs-you first (pi-presence state files)
  #   Project  every session recorded for $PWD
  #   Recent   the 150 most recently touched sessions, all projects
  #
  # ctrl-s cycles those three source modes (television's own binding). Enter
  # prints the session id, so the channel composes:
  #
  #   pi --session (tv pi-sessions)
  #
  # rather than taking over the terminal. alt-s is the exception -- for a
  # session that is running in a tmux pane it switches this client there,
  # which is the one action worth more than a printed id.
  #
  # "Active" is only as good as pi-presence (modules/ai/extensions/pi-presence.nix):
  # pi keeps no open handle on its session JSONL and exports PI_SESSION_FILE
  # only into bash-tool children, so nothing outside the process can map a pid
  # to a session. The extension writes `<agentDir>/live/<id>.json` on every
  # transition instead, which is also where the working/blocked/idle state and
  # the `$TMUX_PANE` correlation come from.
  flake.modules.homeManager.ai =
    { pkgs, ... }:
    let
      # tmux is deliberately absent from both `runtimeInputs`: the tv wrapper
      # already appends one to PATH (shell/television.nix), and inside a tmux
      # popup that has to be the *server's* tmux, not a second store copy.
      list = pkgs.writeShellApplication {
        name = "pi-sessions-list";
        runtimeInputs = with pkgs; [
          jq
          coreutils
          findutils
          gnused
        ];
        text = builtins.readFile ./_pi-sessions/list.bash;
      };
      preview = pkgs.writeShellApplication {
        name = "pi-sessions-preview";
        runtimeInputs = with pkgs; [
          jq
          coreutils
          gnused
        ];
        text = builtins.readFile ./_pi-sessions/preview.bash;
      };
    in
    {
      television.extraChannels.pi-sessions = {
        metadata = {
          name = "pi-sessions";
          description = "pi coding-agent sessions -- live, per-project, and recent";
          requirements = [ "jq" ];
        };

        # The lister emits four tab-separated columns:
        # display, session id, session file, tmux pane. Only the first is
        # shown; the rest feed `output` and the preview. `no_sort` keeps the
        # lister's own ordering (needs-you first, then recency) instead of
        # tv's alphabetical pass -- the ordering is the point of the channel.
        source = {
          command = [
            {
              name = "Active";
              run = "${list}/bin/pi-sessions-list active";
            }
            {
              name = "Project";
              run = "${list}/bin/pi-sessions-list project";
            }
            {
              name = "Recent";
              run = "${list}/bin/pi-sessions-list recent";
            }
          ];
          display = "{split:\t:0}";
          output = "{split:\t:1}";
          no_sort = true;
        };

        preview.command = "${preview}/bin/pi-sessions-preview '{split:\t:2}' '{split:\t:3}'";

        # No `enter` action on purpose: with none defined tv prints the
        # `output` template, which is what makes `pi --session (tv
        # pi-sessions)` work. alt-s (rather than ctrl-s, which cycles the
        # source modes) is the only side effect, and only fires for a session
        # that still has a live pane.
        keybindings.alt-s = "actions:switch";
        actions.switch = {
          description = "Switch this tmux client to the session's pane";
          command = "tmux switch-client -t '{split:\t:3}'";
          mode = "execute";
        };
      };
    };
}
