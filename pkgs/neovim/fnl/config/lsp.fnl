;; LSP configuration

(fn attach-base [_ buf]
  (let [km (require :lib.keymap)
        picker (require :lib.picker)]
    (km.group :<leader>c :Code)
    (km.map :gd #(picker.lsp-definitions) {:desc "Lsp Definitions"})
    (km.map :grr #(picker.lsp-references) {:desc "Lsp References"})
    (km.map :<leader>xs #(picker.lsp-document-symbols)
            {:desc "Document symbols"})
    (km.map :<leader>ca vim.lsp.buf.code_action
            {:desc "Lsp Code Action" :buffer buf})))

(let [blink (require :blink.cmp)
      capabilities (blink.get_lsp_capabilities (vim.lsp.protocol.make_client_capabilities))]
  (vim.lsp.config "*" {: capabilities :on_attach attach-base}))

(vim.lsp.config :luals {:root_markers [:.git :.stylua.toml]})
(vim.lsp.config :fennel-ls {})
(vim.lsp.config :nixd {})
(vim.lsp.config :ts_ls
                {:on_attach (fn [_ buf]
                              (attach-base _ buf)
                              (let [km (require :lib.keymap)]
                                (km.map :<leader>ci
                                        (fn []
                                          (vim.lsp.buf.code_action {:context {:only [:source.addMissingImports.ts
                                                                                     :source.addMissingImports]}
                                                                    :apply true}))
                                        {:desc "Add Missing Imports"})
                                (km.map :<leader>cr
                                        (fn []
                                          (vim.lsp.buf.code_action {:context {:only [:source.organizeImports]}
                                                                    :apply true}))
                                        {:desc "Organize Imports"})))})

(vim.lsp.config :clojure_lsp {})
(vim.lsp.config :jsonls {})
(vim.lsp.config :yamlls {})
(vim.lsp.config :basedpyright {})
(vim.lsp.config :ruff {})

;; OmniSharp (C#/.NET). omnisharp-extended rewires goto/references so they
;; can descend into decompiled metadata / external assemblies.
(vim.lsp.config :omnisharp
                {:on_attach (fn [client buf]
                              (attach-base client buf)
                              (let [km (require :lib.keymap)
                                    ext (require :omnisharp_extended)]
                                (km.map :gd #(ext.lsp_definition)
                                        {:desc "Goto Definition (OmniSharp)"
                                         :buffer buf})
                                (km.map :grr #(ext.lsp_references)
                                        {:desc "References (OmniSharp)"
                                         :buffer buf})
                                (km.map :gI #(ext.lsp_implementation)
                                        {:desc "Goto Implementation (OmniSharp)"
                                         :buffer buf})
                                (km.map :<leader>cD #(ext.lsp_type_definition)
                                        {:desc "Type Definition (OmniSharp)"
                                         :buffer buf})))})

(vim.lsp.enable [:luals :fennel-ls :nixd :ts_ls :clojure_lsp :jsonls :yamlls
                 :basedpyright :ruff :omnisharp])

;; Default inlay hints
(vim.lsp.inlay_hint.enable true)
