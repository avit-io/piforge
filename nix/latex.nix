{ inputs, lib }:

let
  defaultPackages = { pkgs, scheme ? "full" }: [
    pkgs.texlive.combined."scheme-${scheme}"
    pkgs.ghostscript
    pkgs.python3
    pkgs.perl
  ];
in
{
  packagesFor = defaultPackages;

  mkShell = { pkgs, scheme ? "full", extraPackages ? [] }:
    pkgs.mkShell {
      name     = "latex";
      packages = defaultPackages { inherit pkgs scheme; } ++ extraPackages;
    };
}
