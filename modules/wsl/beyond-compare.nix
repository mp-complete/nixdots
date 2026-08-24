{ config, lib, ... }:
{
  options.git.beyondCompare = {
    candidates = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/mnt/c/Program Files/Beyond Compare 5/BComp.exe"
        "/mnt/c/Program Files/Beyond Compare 4/BComp.exe"
        "/mnt/c/Program Files (x86)/Beyond Compare 4/BComp.exe"
        "/mnt/c/Program Files (x86)/Beyond Compare 3/BComp.exe"
      ];
      description = ''
        Where to look for Beyond Compare on the Windows side, most-preferred
        first. Probed at runtime rather than pinned at build time so a BC4 ->
        BC5 upgrade on Windows doesn't need a rebuild, and so a host without
        Beyond Compare installed still evaluates.

        Always `BComp.exe`, never `BCompare.exe`: `BComp.exe` blocks until the
        comparison window closes, which is the entire contract `git difftool`
        and `git mergetool` rely on. `BCompare.exe` returns immediately, so git
        would tear down the temp files (and, for a merge, read back an
        untouched `$MERGED`) while you were still looking at the diff.

        `$BCOMPARE_EXE` overrides the list at runtime.
      '';
    };
  };

  # Beyond Compare as an *opt-in* git difftool/mergetool on WSL. nvimdiff stays
  # the default (development/git.nix); this adds a `bcompare` tool that has to
  # be asked for explicitly -- `git difftool -t bcompare`, or the `gdtb`/`gmtb`
  # abbreviations below.
  #
  # Deliberately not named `bc`: git ships a builtin tool definition under that
  # name which invokes a Linux-native `bcompare` binary, and shadowing a builtin
  # makes `git difftool --tool-help` lie about what will run.
  config.flake.modules.homeManager.wsl =
    { pkgs, ... }:
    let
      bcompare-git = pkgs.writeShellApplication {
        name = "bcompare-git";
        # wslpath is /sbin/wslpath -> /init, provided by the WSL interop layer
        # rather than by any package, so it can't be a runtimeInput. It is on
        # PATH in a normal login shell; the fallback below covers the cases
        # where it isn't (systemd user units, `env -i`, git hooks).
        text = ''
          candidates=(${lib.escapeShellArgs config.git.beyondCompare.candidates})

          exe=''${BCOMPARE_EXE:-}
          if [ -n "$exe" ] && [ ! -x "$exe" ]; then
            echo "bcompare-git: \$BCOMPARE_EXE ($exe) is not an executable." >&2
            exit 127
          fi
          if [ -z "$exe" ]; then
            for candidate in "''${candidates[@]}"; do
              if [ -x "$candidate" ]; then
                exe=$candidate
                break
              fi
            done
          fi
          if [ -z "$exe" ]; then
            {
              echo "bcompare-git: no Beyond Compare executable found. Looked in:"
              printf '  %s\n' "''${candidates[@]}"
              echo "Set BCOMPARE_EXE, or git.beyondCompare.candidates in nixdots."
            } >&2
            exit 127
          fi

          if ! command -v wslpath >/dev/null 2>&1; then
            PATH=$PATH:/sbin
          fi

          # Beyond Compare is a Windows process and cannot resolve a single one
          # of the paths git hands us. Translate each: paths inside the distro
          # become \\wsl.localhost\<distro>\... UNC paths (which is where git's
          # difftool/mergetool temp files live), /mnt/c/... becomes C:\....
          win() { wslpath -w "$1"; }

          mode=''${1:-}
          shift || true

          case "$mode" in
          diff)
            exec "$exe" "$(win "$1")" "$(win "$2")"
            ;;
          merge)
            ours=$1 theirs=$2 base=$3 merged=$4
            # git always exports $BASE, but points it at an empty file when the
            # two sides have no common ancestor. Handing that to BC as the
            # ancestor pane makes every line look conflicted, so fall back to a
            # 2-way merge instead.
            if [ -s "$base" ]; then
              exec "$exe" "$(win "$ours")" "$(win "$theirs")" "$(win "$base")" \
                -mergeoutput="$(win "$merged")"
            else
              exec "$exe" "$(win "$ours")" "$(win "$theirs")" \
                -mergeoutput="$(win "$merged")"
            fi
            ;;
          *)
            echo "usage: bcompare-git diff LOCAL REMOTE" >&2
            echo "       bcompare-git merge LOCAL REMOTE BASE MERGED" >&2
            exit 64
            ;;
          esac
        '';
      };
    in
    {
      home.packages = [ bcompare-git ];

      programs.git.settings = {
        difftool.bcompare.cmd = ''${bcompare-git}/bin/bcompare-git diff "$LOCAL" "$REMOTE"'';
        mergetool.bcompare = {
          cmd = ''${bcompare-git}/bin/bcompare-git merge "$LOCAL" "$REMOTE" "$BASE" "$MERGED"'';
          # BComp.exe exits 0 only when the merge was saved, so git can use the
          # exit status instead of asking "Was the merge successful [y/n]?".
          trustExitCode = true;
        };
      };

      # `-t bcompare` is too long to type on a per-file basis, and abbreviations
      # (rather than aliases) keep the tool name in the command line where it
      # can be edited or dropped -- see development/git.nix for `gdt`/`gmt`.
      programs.fish.shellAbbrs = {
        gdtb = "git difftool -t bcompare";
        gmtb = "git mergetool -t bcompare";
      };
    };
}
