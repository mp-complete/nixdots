;; Git integration
;;   * gitsigns      — gutters, hunk navigation, staging, blame, diff preview
;;   * git-conflict  — conflict-marker resolution in the working-tree buffer

(fn on-attach [bufnr]
  (let [gs (require :gitsigns)
        km (require :lib.keymap)]
    ;; Navigation
    (km.map "]h" #(gs.nav_hunk :next) {:buffer bufnr :desc "Next hunk"})
    (km.map "[h" #(gs.nav_hunk :prev) {:buffer bufnr :desc "Previous hunk"})

    ;; Actions
    (km.map :<leader>ghs #(gs.stage_hunk) {:buffer bufnr :desc "Stage hunk"})
    (km.map :<leader>ghr #(gs.reset_hunk) {:buffer bufnr :desc "Reset hunk"})
    (km.map :<leader>ghs
            #(gs.stage_hunk [(vim.fn.line ".") (vim.fn.line "v")])
            {:buffer bufnr :mode :v :desc "Stage hunk (visual)"})
    (km.map :<leader>ghr
            #(gs.reset_hunk [(vim.fn.line ".") (vim.fn.line "v")])
            {:buffer bufnr :mode :v :desc "Reset hunk (visual)"})
    (km.map :<leader>ghS #(gs.stage_buffer) {:buffer bufnr :desc "Stage buffer"})
    (km.map :<leader>ghu #(gs.undo_stage_hunk) {:buffer bufnr :desc "Undo stage hunk"})
    (km.map :<leader>ghR #(gs.reset_buffer) {:buffer bufnr :desc "Reset buffer"})
    (km.map :<leader>ghp #(gs.preview_hunk) {:buffer bufnr :desc "Preview hunk"})
    (km.map :<leader>ghb #(gs.blame_line {:full true}) {:buffer bufnr :desc "Blame line"})
    (km.map :<leader>ghd #(gs.diffthis) {:buffer bufnr :desc "Diff this"})
    (km.map :<leader>ob #(gs.toggle_current_line_blame) {:buffer bufnr :desc "Toggle line blame"})))

(fn after []
  (let [gs (require :gitsigns)]
    (gs.setup {:on_attach on-attach})))

;; git-conflict resolves conflicts *in place*, in the real file, which is the
;; right tool for the common case: a handful of small conflicts where you just
;; want to pick a side. `git mergetool` (development/git.nix wires it to this
;; same neovim, see config/diff.fnl) stays for the cases that need to see
;; LOCAL/BASE/REMOTE side by side.
;;
;; The plugin parses the `|||||||` ancestor block too, so it understands the
;; zdiff3 markers `merge.conflictStyle` produces.
(fn conflict-after []
  (let [gc (require :git-conflict)
        km (require :lib.keymap)
        au (require :lib.auto-cmd)]
    (gc.setup {;; Buffer-local, and only attached to buffers git reports as
               ;; unmerged:
               ;;   co / ct / cb / c0 — take ours / theirs / both / neither
               ;;   ]x / [x           — next / previous conflict
               :default_mappings true
               :default_commands true
               ;; Deliberately off. The plugin's own implementation calls
               ;; `vim.diagnostic.disable`, which neovim 0.12 removed, and it
               ;; does so from the head of the same `GitConflictDetected`
               ;; handler that installs the mappings above — so turning it on
               ;; silently costs you co/ct/cb/c0. Reimplemented below against
               ;; the current API.
               :disable_diagnostics false})
    ;; A file full of conflict markers parses as nothing in any language, so
    ;; every LSP and linter has an opinion about it until it's resolved.
    (au.group! :git-conflict-diagnostics
               [[:User] {:pattern :GitConflictDetected
                         :callback (fn [ev]
                                     (vim.diagnostic.enable false {:bufnr ev.buf}))}]
               [[:User] {:pattern :GitConflictResolved
                         :callback (fn [ev]
                                     (vim.diagnostic.enable true {:bufnr ev.buf}))}])
    (km.map :<leader>gc "<cmd>GitConflictListQf<cr>"
            {:desc "Conflicts (quickfix)"})))

[{:name :gitsigns.nvim
  :event :DeferredUIEnter
  :after after}
 {:name :git-conflict.nvim
  :event :DeferredUIEnter
  :after conflict-after}]
