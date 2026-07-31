{
  pkgs,
  lib ? pkgs.lib,
  neovim-unwrapped ? pkgs.neovim-unwrapped,
  fennel-ls-nvim-docs,
}:
let
  # Compile Fennel sources to Lua.
  # - .fnlm files are skipped (compile-time macro modules only)
  # - nfnl macros (if-let, when-let, time) available via import-macros
  # - Personal macros from fnl/*.fnlm also available
  fennelCompiled =
    pkgs.runCommand "nvim-fnl-compiled"
      {
        nativeBuildInputs = [ pkgs.luaPackages.fennel ];
      }
      ''
        mkdir -p $out
        cd ${./fnl}
        find . -name '*.fnl' -not -name '*.fnlm' | while read -r f; do
          dir=$(dirname "$f")
          base=$(basename "$f" .fnl)
          mkdir -p "$out/$dir"
          fennel \
            --add-macro-path "${pkgs.vimPlugins.nfnl}/fnl/?.fnlm" \
            --add-macro-path "${pkgs.vimPlugins.nfnl}/fnl/?/init.fnlm" \
            --add-macro-path "${./fnl}/?.fnlm" \
            --add-macro-path "${./fnl}/?/init.fnlm" \
            --compile "$f" > "$out/$dir/$base.lua"
        done
      '';

  # Assemble the full config directory:
  #   $out/init.lua        <- entry point
  #   $out/lua/            <- hand-written Lua + compiled Fennel (shared namespace)
  #   $out/lsp/            <- native LSP server configs
  #
  # Both Lua and Fennel modules use the same require paths:
  #   require("config.options")   -- from lua/ or compiled fnl/
  #   require("plugins.editor")   -- works regardless of source language
  configDir = pkgs.runCommand "nvim-config" { } ''
    mkdir -p $out/lua

    cp ${./init.lua} $out/init.lua

    # Hand-written Lua modules
    if [ -d ${./lua} ]; then
      cp -r ${./lua}/. $out/lua/
    fi

    # LSP server configs (lsp/<name>.lua)
    if [ -d ${./lsp} ]; then
      cp -r ${./lsp} $out/lsp
    fi

    # Ensure directories are writable so compiled Fennel can merge in
    chmod -R u+w $out/lua

    # Compiled Fennel into shared namespace
    cp -r ${fennelCompiled}/. $out/lua/

    # Clean up placeholders
    find $out -name '.gitkeep' -delete
  '';

  pluginSets = import ./plugins.nix { inherit pkgs; };

  # makeNeovimConfig expects a flat list where opt plugins have { optional = true; }
  plugins =
    pluginSets.start
    ++ map (p: {
      plugin = p;
      optional = true;
    }) pluginSets.opt;

  neovimConfig = {
    inherit plugins;

    # Injected into the generated init.lua after provider setup.
    # Plugins are already on the packpath at this point (set via --cmd flags).
    luaRcContent = ''
      vim.opt.rtp:prepend("${configDir}")
      dofile("${configDir}/init.lua")
    '';
  };
  # fennel-ls with Neovim API docset baked in.
  # XDG_DATA_HOME is set only for the fennel-ls process so it finds
  # the nvim docset without touching the user's home directory.
  fennel-ls-docsets = pkgs.runCommand "fennel-ls-docsets" { } ''
    mkdir -p $out/fennel-ls/docsets
    cp ${fennel-ls-nvim-docs}/nvim.lua $out/fennel-ls/docsets/nvim.lua
  '';

  fennel-ls-wrapped = pkgs.symlinkJoin {
    name = "fennel-ls-wrapped";
    paths = [ pkgs.fennel-ls ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/fennel-ls \
        --set XDG_DATA_HOME "${fennel-ls-docsets}"
    '';
  };

  extraPackages = with pkgs; [
    fzf
    fd
    ripgrep

    luajitPackages.fennel

    tree-sitter

    # LSP servers
    typescript-language-server
    lua-language-server
    fennel-ls-wrapped
    nixd
    clojure-lsp
    vscode-langservers-extracted
    yaml-language-server
    basedpyright
    ruff
    # C#/.NET — for legacy .NET Framework (non-SDK) projects built with
    # mono. Note: this is the CoreCLR build of omnisharp-roslyn, so it
    # resolves MSBuild via dotnet-SDK, not mono; see lsp/omnisharp.lua for
    # how it's pointed at mono's reference assemblies.
    omnisharp-roslyn

    # Formatters
    fnlfmt
    nixfmt
    prettierd
    stylua
    csharpier

    # Linters
    statix
    deadnix
    eslint_d

    # Debug adapters
    vscode-js-debug

    # kulala (HTTP client) runtime deps
    openssl
    grpcurl
    websocat
  ];
in
pkgs.wrapNeovimUnstable neovim-unwrapped (
  neovimConfig
  // {
    wrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      (lib.makeBinPath extraPackages)
    ];
  }
)
