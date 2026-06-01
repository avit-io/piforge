# nix/agda.nix
# Chiamato da flake.nix come: import ./nix/agda.nix { inherit inputs lib; }
#
# Esporta:
#   packagesForSystem  system → attrset di derivazioni
#   mkShell            { self, pkgs, version, extraPackages? } → mkShell
#   versionTable       metadata pubblici delle versioni

{ inputs, lib }:

let
  # ── Tabella versioni ────────────────────────────────────────────────────
  # ghc: versione GHC usata per buildare Agda (e il cornelis corrispondente).
  # cornelis v2.7.1 è il primo tag disponibile → supporto da Agda 2.7 in poi.
  versionTable = {
    v27 = {
      agdaVersion   = "2.7.0.1";
      agdaSrc       = inputs.agda-src-2701;
      stdlibVersion = "2.1.1";
      stdlibSrc     = inputs.stdlib-v211;
      ghc           = "ghc98";
      cornelisPin   = {
        rev    = "v2.7.1";
        sha256 = "sha256-h18AeggnOSSjy0RLJIkWsSID1BJTarOV9F1APKusIrE=";
      };
    };
    v28 = {
      agdaVersion   = "2.8.0";
      agdaSrc       = inputs.agda-src-280;
      stdlibVersion = "2.3";
      stdlibSrc     = inputs.stdlib-v23;
      ghc           = "ghc910";
      cornelisPin   = {
        rev    = "8401538b8d5056571827679658331136c38f11be";
        sha256 = "sha256-Z/2hBW/bRb8wtJqBUT8tqgoXg4XqGNvp8L6xw+zHDaU=";
      };
    };
  };

  # ── Builder interni ─────────────────────────────────────────────────────

  buildAgda = { pkgs, src, version, ghc }:
    let
      hlib = pkgs.haskell.lib.compose;
      hp   = pkgs.haskell.packages.${ghc};
    in
    hlib.dontCheck (hlib.dontHaddock (hlib.disableLibraryProfiling
      (hp.developPackage { inherit src; name = "Agda-${version}"; })));

  buildStdlib = { pkgs, src, version }:
    pkgs.stdenv.mkDerivation {
      pname     = "agda-stdlib";
      inherit version src;
      dontBuild = true;
      installPhase = "cp -r . $out";
    };

  buildCornelis = { pkgs, pin, ghc }:
    let
      hp  = pkgs.haskell.lib;
      src = pkgs.fetchFromGitHub {
        owner = "isovector";
        repo  = "cornelis";
        inherit (pin) rev sha256;
      };
    in
    (hp.doJailbreak (pkgs.haskell.packages.${ghc}.callCabal2nix "cornelis" src { })).overrideAttrs (_: {
      doCheck = false;
    });

  # Wrapper: agda con --library-file già cablato allo stdlib dello store.
  # Il consumatore non deve sapere nulla di AGDA_DIR o library files.
  wrapAgda = { pkgs, agda, stdlib, version }:
    let
      libFile = pkgs.writeText "agda-libraries-${version}"
        "${stdlib}/standard-library.agda-lib\n";
    in
    pkgs.runCommand "agda-${version}"
      { buildInputs = [ pkgs.makeWrapper ]; }
      ''
        mkdir -p $out/bin
        makeWrapper ${agda}/bin/agda $out/bin/agda \
          --add-flags "--library-file=${libFile}"
      '';

in
{
  inherit versionTable;

  # ── packages.<system>.* ─────────────────────────────────────────────────
  packagesForSystem = system:
    let pkgs = import inputs.nixpkgs { inherit system; };
    in lib.foldlAttrs (acc: vname: v:
      let
        suffix   = lib.removePrefix "v" vname;
        agda     = buildAgda     { inherit pkgs; src = v.agdaSrc;   version = v.agdaVersion; inherit (v) ghc; };
        stdlib   = buildStdlib   { inherit pkgs; src = v.stdlibSrc; version = v.stdlibVersion; };
        agdaW    = wrapAgda      { inherit pkgs agda stdlib; version = v.agdaVersion; };
        cornelis = buildCornelis { inherit pkgs; pin = v.cornelisPin; inherit (v) ghc; };
      in acc // {
        "agda-${suffix}"     = agdaW;
        "stdlib-${suffix}"   = stdlib;
        "cornelis-${suffix}" = cornelis;
      }
    ) {} versionTable;

  # ── lib.agda.mkShell ────────────────────────────────────────────────────
  # `self` è il flake piforge: viene iniettato da flake.nix, non esposto
  # direttamente ai consumatori (che chiamano piforge.lib.agda.mkShell).
  mkShell = { self, pkgs, version, extraPackages ? [] }:
    let
      suffix = lib.removePrefix "v" version;
      v      = versionTable.${version};
    in
    pkgs.mkShell {
      name     = "agda-${v.agdaVersion}";
      packages = [
        self.packages.${pkgs.system}."agda-${suffix}"
        self.packages.${pkgs.system}."cornelis-${suffix}"
      ] ++ extraPackages;
      shellHook = ''
        echo "agda ${v.agdaVersion} | stdlib ${v.stdlibVersion} | cornelis $(which cornelis)"
      '';
    };
}
