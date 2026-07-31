{
  # Fish shortcuts for driving `pi -p` (non-interactive) from any prompt:
  #
  #   ?  read-only question   -> pi -p, edit/write tools disabled + a
  #                              read-only system-prompt injection
  #   !  command (may write)  -> pi -p with full default tools
  #   ^  continue previous    -> pi -c -p
  #
  # Notes on fish 4.x quirks that drive this design:
  #   * `?` and `^` are free (fish 4 removed the `?` glob and `^` redirect),
  #     so they can be plain functions.
  #   * `!` is a fish *builtin* (logical negation), so it cannot be a function.
  #     We expose it as a command-position abbreviation that rewrites `!` to
  #     the real `pi-cmd` function before the parser sees it.
  #   * `-p` is non-interactive with no TTY, so pi cannot show per-action
  #     confirmations; the only safety lever is which tools are enabled. `?`
  #     therefore excludes edit/write and injects a read-only instruction.
  #
  # The prompt is whatever you type after the symbol; `$argv` is joined into a
  # single message. Free-form text is still subject to normal fish expansion
  # (`*`, `$var`, …) — quote the prompt if it contains shell metacharacters.
  #
  # The functions are defined *inline* in interactiveShellInit rather than via
  # `programs.fish.functions`, because that option writes each one to a
  # separate store derivation named `<name>.fish` — and `?` (a glob char) and
  # `^` (not a legal store-path character) break that path. Inline definitions
  # live directly in config.fish, so no per-function store path is created.
  flake.modules.homeManager.ai = {
    programs.fish = {
      interactiveShellInit = ''
        function ? --description 'pi: read-only question (edit/write tools disabled)'
            pi -p \
                --exclude-tools edit,write \
                --append-system-prompt 'You are operating in READ-ONLY mode. Do NOT create, modify, move, or delete any files, and do not run any command that changes state (no writes, installs, commits, or mutating network calls). Only inspect the project and answer the question. If a change would be required, describe it instead of performing it.' \
                (string join ' ' -- $argv)
        end

        # Target of the `!` abbreviation below. May edit/write files.
        function pi-cmd --description 'pi: run a command that may edit or write files'
            pi -p (string join ' ' -- $argv)
        end

        function ^ --description 'pi: continue the previous session'
            pi -c -p (string join ' ' -- $argv)
        end
      '';

      # `!` can't be a function (builtin), so rewrite it at command position.
      shellAbbrs."!" = {
        position = "command";
        expansion = "pi-cmd";
      };
    };
  };
}
