{
  # Cheats that only make sense from inside WSL -- they shell out to
  # `pwsh.exe` / `powershell.exe` / `wslpath`, none of which exist on a native
  # Linux host, so surfacing them in navi there would be noise at best.
  #
  # `navi.cheatDirs` is declared in shell/navi.nix (the `base` bucket); this is
  # the reason it is an option rather than a literal list.
  flake.modules.homeManager.wsl = {
    navi.cheatDirs.wsl = ./_navi/wsl;
  };
}
