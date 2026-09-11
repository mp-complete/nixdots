{
  description = "miles's NixOS configuration (dendritic)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:denful/import-tree";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agent-skills = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    matt-pocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix.url = "github:Mic92/sops-nix";
    nix-wrapper-modules = {
      # Temporarily pinned to a fork carrying the fix in
      # <https://github.com/milespossing/nix-wrapper-modules/tree/fix/television-themes>:
      # upstream's television module writes `themes` to a directory `tv` never
      # reads, so a configured theme silently degrades to the builtin default.
      # Revert to `github:BirdeeHub/nix-wrapper-modules` once that is merged.
      url = "github:milespossing/nix-wrapper-modules/fix/television-themes";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pi's standalone Bun package. Keep Numtide's own nixpkgs pin so we use
    # its tested, cached package; update Pi with `nix flake update llm-agents`.
    llm-agents.url = "github:numtide/llm-agents.nix";
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Track the newest revision known to be available from Noctalia's Cachix.
    # Keep its pinned nixpkgs: overriding it changes the derivation and misses
    # the upstream binary cache.
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
    worktrunk-flake = {
      url = "github:max-sixty/worktrunk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";

    # fennel-ls docsets for the neovim package's fennel-ls
    fennel-ls-nvim-docs = {
      url = "git+https://git.sr.ht/~micampe/fennel-ls-nvim-docs";
      flake = false;
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
