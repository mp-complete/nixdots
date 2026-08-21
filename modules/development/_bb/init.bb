;; Loaded by the `bb` wrapper via `--init` (modules/development/clojure.nix).
;; Its only job is to make the miles.bb prelude available under short names in
;; interactive contexts: `bb -e` one-liners, `bb repl`, and the `bb
;; nrepl-server` that conjure spawns (which resolves `bb` off PATH, so it goes
;; through the same wrapper).
;;
;; The definitions themselves live in src/miles/bb.clj -- a real namespace on a
;; real classpath, so clj-kondo/clojure-lsp can resolve them in a buffer. This
;; file only refers them in.
;;
;; It is loaded on *every* `bb` invocation from an interactive shell, including
;; `bb somefile.clj`, so these names can shadow a script's own. Scripts run via
;; their `#!/usr/bin/env bb` shebang resolve the real babashka and never see it.

(require '[babashka.classpath :as cp])

;; add-classpath rather than the wrapper passing --classpath: that flag
;; *overrides* a project's bb.edn classpath, which would break `bb` inside any
;; real project.
(cp/add-classpath
 (str (fs/path (or (System/getenv "XDG_CONFIG_HOME")
                   (fs/expand-home "~/.config"))
               "babashka" "src")))

(require '[clojure.pprint :as pp]
         '[clojure.walk :as walk]
         '[babashka.process :as p]
         '[miles.bb :refer [input-file in-str in-lines in-json in-edn
                            json-in json-out sh]])
