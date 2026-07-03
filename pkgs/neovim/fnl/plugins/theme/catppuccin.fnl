{:name :catppuccin-nvim
 :colorscheme [:catppuccin
               :catppuccin-macchiato
               :catppuccin-frappe
               :catppuccin-latte
               :catppuccin-mocha]
 :after (fn [] (let [C (require :catppuccin)]
                 (C.setup {:transparent_background true
                           :float {:transparent true}
                           :integrations {:lualine true
                                          :snacks true}})))}
