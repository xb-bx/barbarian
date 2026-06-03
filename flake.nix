{
  description = "BARbarian - a simple wayland status bar";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "barbarian";
          version = "1.0.5";

          src = ./.;
          hardeningDisable = [ "all" ];

          buildInputs = with pkgs; [
            libGL
            wayland
            libxkbcommon
          ];

          nativeBuildInputs = with pkgs; [
            odin
            clang
          ];

          dontConfigure = true;

          buildPhase = ''
            runHook preBuild
	    make generate
	    odin build . -build-mode:obj -out:barbarian.o -reloc-mode:pic
	    clang *.o -o barbarian -lwayland-client -lwayland-egl -lxkbcommon -lEGL -lm ${pkgs.odin}/share/vendor/stb/lib/stb_truetype.a
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            
            mkdir -p $out/bin
            cp barbarian $out/bin/

            runHook postInstall
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            odin
            ols 
          ];
        };
      }
    );
}
