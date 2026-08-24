-- Neovim configuration entry point
-- Loaded after Nix-managed plugins are on the rtp.
--
-- Lua and compiled Fennel share the same namespace:
--   require("config.options")   -- source: lua/ or fnl/
--   require("plugins.editor")   -- works regardless of source language
--
-- Fennel macros (fnl/*.fnlm) are compile-time only and produce
-- no runtime dependency. Use nfnl macros in .fnl files via:
--   (import-macros {: if-let : when-let} :nfnl.macros)

-- Track startup time for dashboard stats
vim.g.start_time = vim.fn.reltime()

-- Enable the native Lua module cache (before any requires)
vim.loader.enable()

-- Core options and leader keys
require 'config.options'
-- Diff/mergetool setup. Early and plugin-free: `git difftool`/`git mergetool`
-- launch this config with `-d`, so the diff keymaps have to exist before lze
-- gets a chance to lazy-load anything.
require 'config.diff'
require 'config.snacks'

-- Load all plugin specs via lze (opt plugins only)
-- blink.cmp + LSP are loaded lazily on BufReadPost via plugins.lsp
local lze = require 'lze'
lze.load 'plugins'

require 'config.keymaps'

require 'config.theme'

require 'config.alpha'
