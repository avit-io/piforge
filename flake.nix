{
  description = "piforge — library flake per Agda, Haskell, Elm, Gleam";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2511.912939";

    # ── Agda sorgenti ──────────────────────────────────────────────────────
    agda-src-2701.url   = "github:agda/agda/v2.7.0.1";
    agda-src-2701.flake = false;

    agda-src-280.url   = "github:agda/agda/v2.8.0";
    agda-src-280.flake = false;

    # ── Agda stdlib sorgenti ───────────────────────────────────────────────
    # Compatibilità: agda-stdlib/doc/installation-guide.md
    #   2.7.0.1 → stdlib v2.1.1
    #   2.8.0   → stdlib v2.3
    stdlib-v211.url   = "github:agda/agda-stdlib/v2.1.1";
    stdlib-v211.flake = false;

    stdlib-v23.url   = "github:agda/agda-stdlib/v2.3";
    stdlib-v23.flake = false;
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      lib     = nixpkgs.lib;
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAll  = lib.genAttrs systems;

      # Moduli per linguaggio: ricevono inputs (per i sorgenti pinned) e lib.
      agdaMod    = import ./nix/agda.nix    { inherit inputs lib; };
      haskellMod = import ./nix/haskell.nix { inherit inputs lib; };
      elmMod     = import ./nix/elm.nix     { inherit inputs lib; };
      gleamMod   = import ./nix/gleam.nix   { inherit inputs lib; };
      latexMod   = import ./nix/latex.nix   { inherit inputs lib; };

      # Inietta `self` nelle mkShell che ne hanno bisogno (agda, haskell).
      # I consumatori chiamano piforge.lib.<lang>.mkShell senza preoccuparsi
      # di quale `self` usare: viene catturato nella closure qui.
      mkAgdaShell    = args: agdaMod.mkShell    (args // { inherit self; });
      mkHaskellShell = args: haskellMod.mkShell (args // { inherit self; });

    in
    {
      # ── packages ──────────────────────────────────────────────────────────
      # Binari e sorgenti buildati con il nixpkgs di questo flake.
      # Il consumatore li riceve dallo store senza rebuildare niente.
      packages = forAll (system:
        agdaMod.packagesForSystem    system //
        haskellMod.packagesForSystem system //
        elmMod.packagesForSystem     system //
        gleamMod.packagesForSystem   system
      );

      # ── devShells (uso diretto del flake) ──────────────────────────────
      devShells = forAll (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          agda-27  = mkAgdaShell    { inherit pkgs; version = "v27"; };
          agda-28  = mkAgdaShell    { inherit pkgs; version = "v28"; };
          haskell  = mkHaskellShell { inherit pkgs; };
          elm      = elmMod.mkShell    { inherit pkgs; };
          gleam    = gleamMod.mkShell  { inherit pkgs; };
          latex    = latexMod.mkShell  { inherit pkgs; };
          default  = mkAgdaShell    { inherit pkgs; version = "v28"; };
        });

      # ── lib ─────────────────────────────────────────────────────────────
      # API pubblica per i consumatori del flake.
      #
      # Uso tipico:
      #   inputs.piforge.url = "github:avit-io/piforge";
      #
      #   devShells.x86_64-linux.default =
      #     inputs.piforge.lib.agda.mkShell {
      #       pkgs    = nixpkgs.legacyPackages.x86_64-linux;
      #       version = "v28";
      #     };
      lib = {
        agda = {
          mkShell  = mkAgdaShell;
          versions = lib.mapAttrs (_: v: {
            inherit (v) agdaVersion stdlibVersion;
          }) agdaMod.versionTable;
        };
        haskell = {
          mkShell  = mkHaskellShell;
          versions = lib.mapAttrs (_: v: {
            inherit (v) ghcVersion;
          }) haskellMod.ghcVersions;
        };
        elm   = { mkShell = elmMod.mkShell; };
        gleam = { mkShell = gleamMod.mkShell; };
        latex = {
          mkShell     = latexMod.mkShell;
          packagesFor = latexMod.packagesFor;
        };
      };
    };
}
