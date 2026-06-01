# nix/haskell.nix
# Chiamato da flake.nix come: import ./nix/haskell.nix { inherit inputs lib; }
#
# Esporta:
#   packagesForSystem  system → attrset di derivazioni
#   mkShell            { self, pkgs, ghcVersion?, extraPackages? } → mkShell
#   ghcVersions        metadata pubblici delle versioni GHC

{ inputs, lib }:

let
  # ── Tabella versioni GHC ────────────────────────────────────────────────
  # nixAttr: nome dell'attrset in pkgs.haskell.packages.*
  # hls: haskell-language-server è buildato per GHC nel suo stesso attrset.
  ghcVersions = {
    ghc96  = { ghcVersion = "9.6";  nixAttr = "ghc96";  };
    ghc98  = { ghcVersion = "9.8";  nixAttr = "ghc98";  };
    ghc910 = { ghcVersion = "9.10"; nixAttr = "ghc910"; };
    ghc912 = { ghcVersion = "9.12"; nixAttr = "ghc912"; };
  };

in
{
  inherit ghcVersions;

  # ── packages.<system>.* ─────────────────────────────────────────────────
  # Espone solo HLS (GHC e cabal sono in nixpkgs e non serve isolarli).
  packagesForSystem = system:
    let pkgs = import inputs.nixpkgs { inherit system; };
    in lib.foldlAttrs (acc: vname: v:
      acc // {
        "hls-${vname}" = pkgs.haskell.packages.${v.nixAttr}.haskell-language-server;
      }
    ) {} ghcVersions;

  # ── lib.haskell.mkShell ─────────────────────────────────────────────────
  mkShell = { self, pkgs, ghcVersion ? "ghc910", extraPackages ? [] }:
    let
      v  = ghcVersions.${ghcVersion};
      hp = pkgs.haskell.packages.${v.nixAttr};
    in
    pkgs.mkShell {
      name     = "haskell-${v.ghcVersion}";
      packages = [
        hp.ghc
        hp.cabal-install
        self.packages.${pkgs.system}."hls-${ghcVersion}"
        pkgs.zlib.dev
        pkgs.pkg-config
      ] ++ extraPackages;
      shellHook = ''
        echo "ghc ${v.ghcVersion} | hls $(haskell-language-server --version 2>&1 | head -1)"
      '';
    };
}
