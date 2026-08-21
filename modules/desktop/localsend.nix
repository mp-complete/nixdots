{
  flake.modules.nixos.desktop-core =
    { ... }:
    {
      programs.localsend.enable = true;
    };

  # Yazi integration: `<C-s>` hands the selected/hovered entries to the
  # LocalSend GUI. The wrapper registry is global (one yazi for every host), so
  # the plugin ships everywhere and degrades to a clear error notification on
  # hosts without `localsend_app` on PATH — i.e. hosts that don't import
  # desktop-core.
  flake.wrappers.yazi =
    { ... }:
    {
      plugins.localsend = ./_yazi/localsend.yazi;

      settings.keymap.mgr.prepend_keymap = [
        {
          on = "<C-s>";
          run = "plugin localsend";
          desc = "Send selection via LocalSend";
        }
      ];
    };
}
