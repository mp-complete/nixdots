;; conform.nvim — formatter integration
;; Format on save with per-filetype formatters.

(fn after []
  (let [conform (require :conform)
        km (require :lib.keymap)]
    (conform.setup {:formatters_by_ft {:fennel [:fnlfmt]
                                       :lua [:stylua]
                                       :nix [:nixfmt]
                                       :javascript [:eslint_d :prettierd]
                                       :typescript [:eslint_d :prettierd]
                                       :javascriptreact [:eslint_d :prettierd]
                                       :typescriptreact [:eslint_d :prettierd]
                                       :json [:prettierd]
                                       :jsonc [:prettierd]
                                       :cs [:csharpier]
                                       :yaml [:prettierd]
                                       :html [:prettierd]
                                       :css [:prettierd]
                                       :markdown [:prettierd]}
                    :format_on_save (fn [bufnr]
                                      (when (not (or vim.g.disable_autoformat
                                                     (. vim.b bufnr
                                                        :disable_autoformat)))
                                        {:timeout_ms 500
                                         :lsp_format :fallback}))})
    (km.map :<leader>cf #(conform.format {:async true :lsp_format :fallback})
            {:desc "Format buffer"})))

{:name :conform.nvim :event [:BufReadPost :BufWritePre] : after}
