{ inputs, lib }:

let
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

  buildAgda = { pkgs, src, version, ghc }:
    let
      hlib = pkgs.haskell.lib.compose;
      hp   = pkgs.haskell.packages.${ghc};
    in
    hlib.dontCheck (hlib.dontHaddock (hlib.disableLibraryProfiling
      (hp.developPackage { root = src; name = "Agda-${version}"; })));

  # Pre-compila lib/prim (Agda.Primitive & co.) durante il build nix.
  # Al primo avvio agda scrive le .agdai di lib/prim nella Agda_datadir;
  # se quella dir è lo store (read-only) crasha con EROFS. Soluzione: eseguiamo
  # agda una volta durante il build (dove $out è scrivibile) → le .agdai
  # vengono scritte lì. A runtime Agda_datadir punta a questo store path
  # già popolato → nessuna scrittura.
  buildAgdaData = { pkgs, agda, agdaVersion }:
    let agdaAny = agda.data or agda;
    in
    pkgs.runCommand "agda-data-${agdaVersion}" {
      nativeBuildInputs = [ pkgs.findutils ];
    } ''
      _prim=$(find ${agdaAny} ${agda} -name "prim" -type d 2>/dev/null | head -1)
      if [ -z "$_prim" ]; then
        echo "ERROR: lib/prim non trovato in agda derivation" >&2
        exit 1
      fi
      _data=$(dirname "$(dirname "$_prim")")
      mkdir -p $out
      cp -r "$_data/." $out/
      chmod -R u+w $out

      export Agda_datadir=$out
      export AGDA_DIR=$TMPDIR/home
      mkdir -p $AGDA_DIR

      # Compila ogni file in lib/prim in modo che _build/ venga pre-popolato
      # mentre $out è ancora scrivibile. A runtime agda trova le interfacce
      # già pronte e non prova a scrivere nello store.
      find $out/lib/prim -name "*.agda" | sort | while IFS= read -r _f; do
        ${agda}/bin/agda "$_f" 2>/dev/null || true
      done

      if [ ! -d "$out/lib/prim/_build" ]; then
        echo "ERROR: lib/prim/_build non creato — la pre-compilazione è fallita" >&2
        exit 1
      fi
    '';

  # La stdlib viene distribuita come sorgente pura.
  # Agda in Agda 2.8+ scrive i compiled interface in _build/ relativo alla
  # library root (dove sta standard-library.agda-lib). Se quella root è nello
  # store nix, fallisce con EROFS. Soluzione: wrapAgda copia la stdlib in
  # ~/.cache/piforge/stdlib-<ver>/ alla prima invocazione.
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

  # Wrapper con stdlib.
  # - Agda_datadir → lib/prim pre-compilato (nello store, read-only ok)
  # - stdlib       → copiata in ~/.cache/piforge/stdlib-<ver>/ al primo uso
  #                  (scrivibile: agda ci scrive _build/ senza problemi)
  wrapAgda = { pkgs, agda, agdaData, stdlib, version, stdlibVersion }:
    pkgs.writeShellScriptBin "agda" ''
      _base="''${XDG_CACHE_HOME:-$HOME/.cache}/piforge"
      _stdlib="$_base/stdlib-${stdlibVersion}"
      _libfile="$_base/libraries-${version}"
      if [ ! -d "$_stdlib" ]; then
        mkdir -p "$_stdlib"
        cp -r ${stdlib}/. "$_stdlib/"
        chmod -R u+w "$_stdlib"
        printf '%s\n' "$_stdlib/standard-library.agda-lib" > "$_libfile"
      fi
      Agda_datadir=${agdaData} exec ${agda}/bin/agda --library-file="$_libfile" "$@"
    '';

  # Wrapper senza stdlib (useRuntimeLibraries): solo Agda_datadir.
  # L'utente gestisce AGDA_DIR nel shellHook (con una stdlib scrivibile).
  wrapAgdaRuntime = { pkgs, agda, agdaData }:
    pkgs.writeShellScriptBin "agda" ''
      Agda_datadir=${agdaData} exec ${agda}/bin/agda "$@"
    '';

in
{
  inherit versionTable;

  packagesForSystem = system:
    let pkgs = import inputs.nixpkgs { localSystem = { inherit system; }; };
    in lib.foldlAttrs (acc: vname: v:
      let
        suffix   = lib.removePrefix "v" vname;
        agda     = buildAgda     { inherit pkgs; src = v.agdaSrc; version = v.agdaVersion; inherit (v) ghc; };
        agdaData = buildAgdaData { inherit pkgs agda; agdaVersion = v.agdaVersion; };
        stdlib   = buildStdlib   { inherit pkgs; src = v.stdlibSrc; version = v.stdlibVersion; };
        agdaW    = wrapAgda      { inherit pkgs agda agdaData stdlib; version = v.agdaVersion; stdlibVersion = v.stdlibVersion; };
        cornelis = buildCornelis { inherit pkgs; pin = v.cornelisPin; inherit (v) ghc; };
      in acc // {
        "agda-${suffix}"      = agdaW;
        "agda-data-${suffix}" = agdaData;
        "stdlib-${suffix}"    = stdlib;
        "cornelis-${suffix}"  = cornelis;
      }
    ) {} versionTable;

  mkShell = { self, pkgs, version, extraPackages ? [], shellHook ? "", useRuntimeLibraries ? false }:
    let
      suffix   = lib.removePrefix "v" version;
      v        = versionTable.${version};
      agdaData = self.packages.${pkgs.system}."agda-data-${suffix}";
      cornelis = self.packages.${pkgs.system}."cornelis-${suffix}";

      agdaBin =
        if useRuntimeLibraries
        then
          let rawAgda = buildAgda { inherit pkgs; src = v.agdaSrc; version = v.agdaVersion; inherit (v) ghc; };
          in wrapAgdaRuntime { inherit pkgs agdaData; agda = rawAgda; }
        else
          self.packages.${pkgs.system}."agda-${suffix}";
    in
    pkgs.mkShell {
      name     = "agda-${v.agdaVersion}";
      packages = [ agdaBin cornelis ] ++ extraPackages;
      shellHook = ''
        echo "agda ${v.agdaVersion}${lib.optionalString (!useRuntimeLibraries) " | stdlib ${v.stdlibVersion}"} | cornelis $(which cornelis)"
      '' + shellHook;
    };
}
