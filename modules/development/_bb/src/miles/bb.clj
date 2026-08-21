(ns miles.bb
  "Personal babashka prelude: the helpers that make one-liners and scratch
  snippets short.

  This is a real namespace on a real classpath (~/.config/babashka/src, put
  there by modules/development/clojure.nix) rather than a pile of defs in an
  --init file, so that clj-kondo/clojure-lsp can see it. A buffer that opens
  with

    (require '[miles.bb :refer [in-lines]])

  gets completion, jump-to-definition and docstrings, instead of a wall of
  `Unresolved symbol`.

  ~/.config/babashka/init.bb requires this with :refer for interactive use, so
  `bb -e` one-liners and conjure's auto-REPL still get the short names for
  free. Scripts under ~/bb run through a `#!/usr/bin/env bb` shebang, which
  does *not* load init.bb and does not have this on its classpath -- keep those
  self-contained."
  (:require [babashka.fs :as fs]
            [babashka.process :as p]
            [cheshire.core :as json]
            [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]))

(defn sh
  "Run a command, returning its stdout trimmed. Throws on a non-zero exit.
  Takes the same arguments as babashka.process/shell:
    (sh \"git log --oneline -5\")
    (sh \"git\" \"log\" \"--oneline\" \"-5\")"
  [& args]
  (str/trim (:out (apply p/shell {:out :string} args))))

(defn json-in
  "Parse the whole of *in* as one JSON value, keywordizing map keys.
  For pipelines (`bb -e`), where stdin really is the data."
  []
  (json/parse-stream (io/reader *in*) true))

(defn json-out
  "Print x to stdout as pretty JSON."
  [x]
  (println (json/generate-string x {:pretty true})))

;; Captured stdin. `bbin` / `bbe` write the piped data to this file and these
;; read it back.
;;
;; This exists because *in* is unusable for REPL-driven work. It is a one-shot
;; stream, and conjure's auto-REPL is a *separate* `bb nrepl-server` process
;; spawned by neovim -- its stdin is that job's pty, so `(slurp *in*)` there is
;; "". Reading a file instead is re-readable, survives re-evaluation, and gives
;; the editor REPL and the shell the exact same data.
;;
;; The tradeoff is that the input is fully realised: no infinite streams. Use
;; `bb -i --stream` (the `bbs` abbreviation) for those.

(def input-file
  "Where `bbin` / `bbe` park piped stdin. Override with $BB_INPUT."
  (or (System/getenv "BB_INPUT")
      (str (fs/expand-home "~/.cache/babashka/stdin"))))

(defn in-str
  "The captured stdin as one string (\"\" if nothing has been captured)."
  []
  (if (fs/exists? input-file) (slurp input-file) ""))

(defn in-lines
  "The captured stdin as a vector of lines."
  []
  (let [s (in-str)]
    (if (str/blank? s) [] (str/split-lines s))))

(defn in-json
  "The captured stdin parsed as one JSON value, keywordizing map keys."
  []
  (json/parse-string (in-str) true))

(defn in-edn
  "The captured stdin parsed as one EDN value."
  []
  (edn/read-string (in-str)))
