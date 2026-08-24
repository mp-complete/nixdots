;; Diff-mode ergonomics.
;;
;; `git difftool` / `git mergetool` are configured to launch this neovim
;; (`diff.tool` / `merge.tool` = nvimdiff, modules/development/git.nix), which
;; means neovim starts with `-d` and a prebuilt window layout. Nothing here may
;; depend on a plugin: lze plugins load on DeferredUIEnter, long after the
;; mergetool layout exists and possibly after the first `:diffget`.

(local au (require :lib.auto-cmd))
(local km (require :lib.keymap))

;; Neovim already defaults to
;; `internal,filler,closeoff,indent-heuristic,inline:char,linematch:40`.
;; The additions:
;;   * algorithm:histogram -- the same algorithm as `diff.algorithm` in
;;     modules/development/git.nix, so a hunk in `:diffthis` is the same hunk
;;     `git diff` printed a second ago
;;   * linematch:60 -- how large a hunk neovim will still try to re-align
;;     line-by-line before giving up and rendering one solid removed/added
;;     block. 40 is low enough that medium-sized edits lose their alignment
;;   * vertical -- side-by-side `:diffsplit`/`:diffthis`, rather than stacked
(set vim.opt.diffopt
     ["internal"
      "filler"
      "closeoff"
      "indent-heuristic"
      "inline:char"
      "algorithm:histogram"
      "linematch:60"
      "vertical"])

;; Filler lines (where one side has nothing) default to a solid run of `-`,
;; which reads as "deleted content" rather than "no content". Appended, not
;; assigned: 'fillchars' is a dict option and a bare set would drop `eob`,
;; `fold`, and the window separators the theme relies on.
(vim.opt.fillchars:append {:diff "╱"})

;; Mergetool keymaps.
;;
;; git's vimdiff backend opens LOCAL / BASE / REMOTE read-only across the top
;; and the writable MERGED below (`mergetool.nvimdiff.layout`). Resolving a
;; conflict means pulling a hunk out of one of the read-only panes into MERGED,
;; which vanilla vim spells `:diffget LOCAL` -- the argument is matched against
;; buffer names, and git names its temp files `<file>_LOCAL_<pid>` and friends.
;;
;; These are buffer-local and only attached while the window is actually in
;; diff mode, so `<leader>1` and friends stay free in normal editing.
(fn attach []
  (when (and vim.wo.diff (not vim.b.diff_keymaps))
    (set vim.b.diff_keymaps true)
    (let [buffer (vim.api.nvim_get_current_buf)]
      (km.map :<leader>1 "<cmd>diffget LOCAL<cr>"
              {: buffer :desc "Diff: take LOCAL (ours)"})
      (km.map :<leader>2 "<cmd>diffget BASE<cr>"
              {: buffer :desc "Diff: take BASE (ancestor)"})
      (km.map :<leader>3 "<cmd>diffget REMOTE<cr>"
              {: buffer :desc "Diff: take REMOTE (theirs)"})
      ;; After editing MERGED by hand the highlighting goes stale until
      ;; something forces a re-diff.
      (km.map :<leader>gu "<cmd>diffupdate<cr>" {: buffer :desc "Diff: refresh"})
      ;; The two ways out of `git mergetool`, made explicit because getting
      ;; them wrong is expensive: `:wqall` saves MERGED and reports the file
      ;; resolved, `:cquit` exits non-zero so git keeps the conflict markers.
      ;; Plain `:qa!` reports *success* while discarding the resolution.
      (km.map :<leader>gw "<cmd>wqall<cr>"
              {: buffer :desc "Diff: save + finish mergetool"})
      (km.map :<leader>gq "<cmd>cquit<cr>"
              {: buffer :desc "Diff: abort mergetool (:cq)"}))))

;; VimEnter covers `nvim -d` and the window the mergetool layout leaves us in;
;; BufWinEnter/WinEnter cover the other panes as they are visited; OptionSet
;; covers `:diffthis` / `:diffsplit` / gitsigns' diffthis at runtime, which
;; VimEnter has long since missed.
(au.group! :diff-mode
           [[:VimEnter :BufWinEnter :WinEnter] {:callback attach}]
           [[:OptionSet] {:pattern :diff :callback attach}])
