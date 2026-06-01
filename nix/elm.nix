# nix/elm.nix
# Elm è monolitico (v0.19.x); nessun multi-versioning necessario.
# Tutto arriva da nixpkgs, nessun packages.* esposto.

{ inputs, lib }:

{
  packagesForSystem = _system: {};

  # ── lib.elm.mkShell ─────────────────────────────────────────────────────
  mkShell = { pkgs, extraPackages ? [] }:
    pkgs.mkShell {
      name     = "elm";
      packages = with pkgs; [
        elmPackages.elm
        elmPackages.elm-format
        elmPackages.elm-language-server
        elmPackages.elm-test
        elmPackages.elm-review
      ] ++ extraPackages;
      shellHook = ''
        echo "elm $(elm --version)"
        export ELM_HOME="$PWD/.elm"
        mkdir -p "$ELM_HOME"
      '';
    };
}
