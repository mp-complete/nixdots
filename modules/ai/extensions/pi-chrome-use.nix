{ ... }:
{
  # pi-chrome-use — CDP-only browser execution for Pi. The WSL wrapper pairs
  # it with agent-browser-edge-bridge so browser_execute reaches only the
  # dedicated Windows Edge profile.
  # https://github.com/citrolabs/pi-chrome-use
  pi.extensions.pi-chrome-use = {
    pname = "pi-chrome-use";
    version = "1.1.1";
    hash = "sha512-dSxkSuKImPkNp3WPIDIaEaUIxYzvG1WtH+8sTb/Bp3fBAIDCndn8LK1JerV3VMlVX1OHqFvuhgf8k7jjmr644g==";

    # Upstream leaves the persistent CDP WebSocket and its timeout timer alive
    # after non-interactive Pi runs complete. Close the per-session connection
    # on session_shutdown and make the watchdog timer non-owning.
    build =
      {
        pkgs,
        src,
        meta,
        passthru,
        unscoped,
        ...
      }:
      pkgs.runCommand "pi-ext-${unscoped}-1.1.1"
        {
          inherit src meta passthru;
          nativeBuildInputs = [ pkgs.patch ];
        }
        ''
          mkdir -p "$out"
          tar -xzf "$src" --strip-components=1 -C "$out"
          patch --fuzz=0 -d "$out" -p1 < ${./_patches/pi-chrome-use-session-lifecycle.patch}
        '';
  };
}
