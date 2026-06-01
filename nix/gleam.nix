# nix/gleam.nix
# Gleam + Erlang/OTP. Nessun multi-versioning: gleam è in rapida evoluzione
# e nixpkgs unstable tiene il binario aggiornato.
# erlangVersion permette di scegliere la versione di OTP se necessario.

{ inputs, lib }:

{
  packagesForSystem = _system: {};

  # ── lib.gleam.mkShell ───────────────────────────────────────────────────
  mkShell = { pkgs, erlangVersion ? "erlang_27", extraPackages ? [] }:
    let
      beamPkgs = pkgs.beam.packagesWith pkgs.beam.interpreters.${erlangVersion};
    in
    pkgs.mkShell {
      name     = "gleam";
      packages = [
        pkgs.gleam
        beamPkgs.erlang
        beamPkgs.rebar3
        pkgs.inotify-tools
      ] ++ extraPackages;
      shellHook = ''
        echo "gleam $(gleam --version) | erl $(erl -eval 'halt()' -noshell 2>&1 | head -1)"
        export ERL_AFLAGS="-kernel shell_history enabled"
      '';
    };
}
