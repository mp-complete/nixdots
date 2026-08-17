{
  perSystem =
    { pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          bashInteractive
          nodejs
          sops
        ];
      };
    };
}
