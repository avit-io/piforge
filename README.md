# piforge

Library flake for Agda, Haskell, Elm and Gleam development environments.

Authoritative on nixpkgs and toolchain versions: binaries are built here and
delivered to consumers via the Nix store — no rebuilds on the consumer side.

## Supported languages

| Language | Versions |
|----------|----------|
| Agda     | 2.7.0.1, 2.8.0 (+ matching stdlib and cornelis) |
| Haskell  | GHC 9.6, 9.8, 9.10, 9.12 (+ HLS) |
| Elm      | 0.19.x |
| Gleam    | latest in nixpkgs |
| LaTeX    | TeX Live (scheme-full by default) + Ghostscript |

## Usage as a library

Add piforge as a flake input and call the appropriate `mkShell`:

```nix
{
  inputs = {
    nixpkgs.follows = "piforge/nixpkgs";
    piforge.url     = "github:avit-io/piforge";
  };

  outputs = { self, nixpkgs, piforge }:
    let pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      devShells.x86_64-linux = {

        agda = piforge.lib.agda.mkShell {
          inherit pkgs;
          version       = "v28";          # "v27" | "v28"
          extraPackages = [ pkgs.just ];   # optional
        };

        haskell = piforge.lib.haskell.mkShell {
          inherit pkgs;
          ghcVersion    = "ghc910";        # "ghc96" | "ghc98" | "ghc910" | "ghc912"
          extraPackages = [];
        };

        elm = piforge.lib.elm.mkShell { inherit pkgs; };

        gleam = piforge.lib.gleam.mkShell {
          inherit pkgs;
          erlangVersion = "erlang_27";     # optional, default erlang_27
        };

        latex = piforge.lib.latex.mkShell {
          inherit pkgs;
          scheme = "full";                 # optional, default "full"
        };

      };
    };
}
```

### Agda con librerie runtime (es. IAL)

Quando la libreria non è stdlib ma un progetto esterno con sorgenti mutabili
(agda scrive `.agdai` accanto ai sorgenti), usare `useRuntimeLibraries = true`.
In questo caso agda usa `$AGDA_DIR/libraries` risolto a runtime invece di un
percorso fisso nello store. La configurazione di `$AGDA_DIR` va nel `shellHook`.

```nix
default = piforge.lib.agda.mkShell {
  inherit pkgs;
  version             = "v27";
  useRuntimeLibraries = true;
  extraPackages       = piforge.lib.latex.packagesFor { inherit pkgs; };
  shellHook           = ''
    mkdir -p .agda-local-work
    export AGDA_DIR="$PWD/.agda-local-work"

    if [ ! -d "$AGDA_DIR/mylib" ]; then
      cp -r ''${mylib}/. "$AGDA_DIR/mylib/"
      chmod -R u+w "$AGDA_DIR/mylib"
    fi

    AGDA_LIB_FILE=$(find "$AGDA_DIR/mylib" -maxdepth 1 -name "*.agda-lib" | head -1)
    echo "$AGDA_LIB_FILE" > "$AGDA_DIR/libraries"
  '';
};
```

## Direct use

```bash
nix develop github:avit-io/piforge                  # Agda 2.8 (default)
nix develop github:avit-io/piforge#agda-27
nix develop github:avit-io/piforge#haskell
nix develop github:avit-io/piforge#elm
nix develop github:avit-io/piforge#gleam
nix develop github:avit-io/piforge#latex
```

## Agda: stdlib vs IAL

The Agda shell wraps the `agda` binary with `--library-file` pointing to the
stdlib already in the Nix store. If a project needs a different library (e.g.
the Iowa Agda Library), add a `shellHook` that overwrites `$AGDA_DIR/libraries`
after entering the shell, or set `--library-file` explicitly.

## Introspection

```nix
# available versions metadata
piforge.lib.agda.versions
# → { v27 = { agdaVersion = "2.7.0.1"; stdlibVersion = "2.1.1"; };
#     v28 = { agdaVersion = "2.8.0";   stdlibVersion = "2.3"; }; }

piforge.lib.haskell.versions
# → { ghc96 = { ghcVersion = "9.6"; }; ... }
```

## Structure

```
flake.nix        inputs + output assembly
nix/
  agda.nix       version table, builders, mkShell
  haskell.nix    GHC version table, mkShell
  elm.nix        mkShell
  gleam.nix      mkShell
```
