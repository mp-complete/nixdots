;; Seamless directional navigation and resizing of neovim splits +
;; terminal multiplexer panes (tmux, kitty). The multiplexer
;; is auto-detected at runtime via env vars (e.g. $TMUX).
;;
;; Zellij integration is handled separately by zellij-nav.nvim, which
;; only activates when $ZELLIJ is set.

(fn after []
  (let [smart-splits (require :smart-splits)
        key (require :lib.keymap)]
    (smart-splits.setup {:at_edge :stop
                         :default_amount 3})
    ;; Navigation
    (key.map :<C-h> smart-splits.move_cursor_left  {:desc "Move to left split"})
    (key.map :<C-j> smart-splits.move_cursor_down  {:desc "Move to below split"})
    (key.map :<C-k> smart-splits.move_cursor_up    {:desc "Move to above split"})
    (key.map :<C-l> smart-splits.move_cursor_right {:desc "Move to right split"})
    ;; Resize
    (key.map :<M-h> smart-splits.resize_left  {:desc "Resize split left"})
    (key.map :<M-j> smart-splits.resize_down  {:desc "Resize split down"})
    (key.map :<M-k> smart-splits.resize_up    {:desc "Resize split up"})
    (key.map :<M-l> smart-splits.resize_right {:desc "Resize split right"})))

{:name :smart-splits.nvim
 :event :DeferredUIEnter
 : after}
