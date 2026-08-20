{ ... }:
{
  # pi-presence — publishes each pi session's state (working / blocked / idle)
  # to `<agentDir>/live/<session id>.json` on every transition, together with
  # its cwd, branch, model, pid and `$TMUX_PANE`.
  #
  # This is the only way to know what a running pi is doing from outside it:
  # pi holds no open handle on its session JSONL and exports PI_SESSION_FILE
  # only into bash-tool children, so /proc gives you a pid and a cwd and
  # nothing else. Consumed here by the `pi-sessions` tv channel
  # (modules/ai/pi-sessions.nix); upstream also ships a `pi-presence-watch`
  # reader and a menubar plugin, neither of which is packaged.
  #
  # Zero runtime deps, no lifecycle scripts, no network. `notify` defaults to
  # false and stays that way — desktop notifications are the `notify`
  # extension's job here.
  # https://github.com/navbytes/pi-presence
  pi.extensions.pi-presence = {
    pname = "pi-presence";
    version = "0.2.0";
    hash = "sha512-+CiWlfEsYCYWLc8xwk9oqtNZlP98DAy6H4DwFQ6Bb9toqYVTXtaaziZEYIqrSfaIjJiGClZkWN1aTEyYKBLkqA==";
  };
}
