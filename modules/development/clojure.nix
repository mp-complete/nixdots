{
  # Clojure/babashka. The system layer installs the toolchain; the home layer
  # is about using babashka *as a shell tool* -- a prelude for one-liners, fish
  # abbreviations for the pipe-friendly flag combinations, and a writable
  # ~/bb on PATH for scripts that outgrow a one-liner.
  flake.modules.nixos.dev =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        clojure
        neil
        babashka
        # EDN <-> JSON <-> YAML <-> transit on the command line, with the same
        # pretty-printer bb uses. The glue that lets bb sit in a pipeline next
        # to jq (shell/tools.nix) instead of hand-rolling parse/generate calls.
        jet
      ];
    };

  flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      # `bb` shadowed by a wrapper that preloads ~/.config/babashka/init.bb.
      # The home profile precedes /run/current-system/sw/bin on PATH, so this
      # is the `bb` an interactive shell finds, while `#!/usr/bin/env bb`
      # shebangs inside scripts resolve the system babashka and stay pristine.
      #
      # --init costs ~4ms on top of bb's ~20ms startup, which is what makes it
      # tolerable to have in a pipeline at all.
      #
      # Caveat: SubstrateVM options (-Xmx...) must precede global options, so
      # `bb -Xmx256M ...` needs the real binary at
      # /run/current-system/sw/bin/bb.
      home.packages = [
        (pkgs.writeShellScriptBin "bb" ''
          exec ${pkgs.babashka}/bin/bb \
            --init "''${XDG_CONFIG_HOME:-$HOME/.config}/babashka/init.bb" "$@"
        '')
      ];

      xdg.configFile = {
        "babashka/init.bb".source = ./_bb/init.bb;
        "babashka/bb.edn".source = ./_bb/bb.edn;
        # The prelude as a real namespace on a real classpath, so clj-kondo /
        # clojure-lsp resolve it. bb.edn's :paths puts this on the classpath;
        # init.bb add-classpath's it for one-liners run from anywhere else.
        "babashka/src/miles/bb.clj".source = ./_bb/src/miles/bb.clj;
        # miles.bb is a library for one-liners; nothing in this little project
        # consumes it, so clojure-lsp's unused-public-var would flag every
        # helper. clj-kondo writes .cache/ and imports/ next to this file, so
        # only the config itself is store-managed.
        "babashka/.clj-kondo/config.edn".source = ./_bb/clj-kondo-config.edn;
      };

      # Scripts scaffolded by `bbnew` land here. Deliberately *not* store-
      # managed: the point is a place to write a script in ten seconds and
      # iterate on it, without a rebuild in the loop. Promote anything that
      # earns its keep into this flake.
      home.sessionPath = [ "$HOME/bb" ];

      # fish abbreviations, matching development/worktrunk.nix: the expansion
      # lands in the buffer, so the one-liner is visible and editable before it
      # runs (and atuin records what actually ran). setCursor puts the point
      # inside the quoted Clojure form.
      #
      # The bb flags being wrapped, all of which only work with -e:
      #   -i  *input* = lazy seq of stdin lines      -o  print result as lines
      #   -I  *input* = lazy seq of stdin EDN values -O  print result as EDN
      #   --stream    one value per iteration rather than the whole seq
      programs.fish.shellAbbrs =
        let
          cursor = expansion: {
            inherit expansion;
            setCursor = "%";
          };
        in
        {
          # lines in, lines out: ls | bbl '(filter (fn [f] (str/ends-with? f ".nix")) *input*)'
          bbl = cursor "bb -i -o -e '%'";
          # EDN in, EDN out
          bbn = cursor "bb -I -O -e '%'";
          # streaming lines: constant memory, works on `tail -f`
          bbs = cursor "bb -i --stream -o -e '%'";
          # JSON in, JSON out, via the init.bb helpers
          bbj = cursor "bb -e '(json-out (-> (json-in) %))'";

          # project bb.edn
          bbt = "bb tasks";
          bbrun = "bb run";
          # global bb.edn (~/.config/babashka/bb.edn): `bbg tasks`, `bbg scripts`
          bbg = "bb --config $HOME/.config/babashka/bb.edn";
          bbnew = cursor "bb --config $HOME/.config/babashka/bb.edn new %";

          # jet: format conversion at the ends of a bb pipeline
          j2e = "jet --from json --to edn --keywordize";
          e2j = "jet --from edn --to json";
          y2e = "jet --from yaml --to edn --keywordize";

          # A standalone nREPL server, for connecting an editor to a project
          # rather than to the scratch buffer. Conjure starts its own on a
          # random port (see `bbin` below), so this is only for the cases where
          # you want a known port or a server outliving nvim.
          bbnrepl = "bb nrepl-server localhost:1667";
        };

      # `bbe` opens $EDITOR because fish has no heredocs, which makes anything
      # past a single line painful to type at the prompt. Piped stdin is saved
      # to a file rather than fed to the snippet on *in*, because *in* is
      # exactly what breaks REPL-driven work: it is one-shot, and conjure's
      # auto-REPL is a separate `bb nrepl-server` process spawned by neovim
      # whose stdin is that job's pty. miles.bb's in-str/in-lines/in-json/in-edn
      # read the file instead, so the snippet behaves identically whether it is
      # run by `bber` or evaluated form-by-form from the editor.
      #
      # The scratch file lives *next to* ~/.config/babashka/bb.edn on purpose:
      # that is how clojure-lsp finds a project root, and hence a classpath
      # containing miles.bb. Conjure resolves `bb` off PATH, so its auto-REPL
      # is the wrapper above and the same helpers are live in the REPL session.
      programs.fish.functions = {
        bbin = {
          description = "Capture piped stdin for babashka's in-str/in-lines/in-json/in-edn";
          body = ''
            set -l dir $HOME/.cache/babashka
            mkdir -p $dir
            if isatty stdin
                echo "bbin: nothing piped in" >&2
                return 1
            end
            cat >$dir/stdin
            echo "captured "(wc -l <$dir/stdin | string trim)" lines to $dir/stdin" >&2
          '';
        };

        bbe = {
          # No $EDITOR in the description: home-manager emits it inside a
          # double-quoted `--description="..."`, so it would expand at
          # definition time.
          description = "Edit a babashka snippet in your editor, then run it against the captured stdin";
          body = ''
            mkdir -p $HOME/.cache/babashka
            set -l script $HOME/.config/babashka/scratch.clj

            # Capture stdin first: the snippet runs after the editor exits.
            if not isatty stdin
                cat >$HOME/.cache/babashka/stdin
            end

            if not test -s $script
                printf '%s\n' \
                    "(require '[miles.bb :refer [in-str in-lines in-json in-edn json-out sh]])" \
                    "" \
                    ";; Scratch snippet -- rerun without editing via bber." \
                    ";; Piped stdin is in (in-str) / (in-lines) / (in-json) / (in-edn), and is" \
                    ";; re-readable, so conjure can evaluate these forms as many times as you like." \
                    ";; Keep the require above: it is what clojure-lsp resolves the names through." \
                    ";; Do not add an (ns ...) form -- conjure would then evaluate in that ns" \
                    ";; rather than in `user`, where init.bb's short names live." \
                    "" \
                    "(run! println (in-lines))" >$script
            end

            set -l editor $EDITOR
            test -n "$editor"; or set editor vim
            $editor $script </dev/tty >/dev/tty
            bber
          '';
        };

        bber = {
          description = "Rerun the last bbe snippet against the captured stdin";
          body = ''
            set -l script $HOME/.config/babashka/scratch.clj
            if not test -f $script
                echo "no snippet yet -- run bbe first" >&2
                return 1
            end
            # /dev/null rather than the terminal: a snippet still using *in*
            # would otherwise sit there waiting for keyboard input.
            bb -f $script </dev/null
          '';
        };
      };
    };
}
