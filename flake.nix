{
  description = "Development environment for pokeemerald-rogue";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Keep the CI-compatible host compiler available after nixpkgs-unstable
    # stopped shipping gcc12 as a package.
    nixpkgs-gcc12.url = "github:NixOS/nixpkgs/9d48c58a87a36ffd33b18a02c62456c72ef85a47";
    agbcc = {
      url = "github:pret/agbcc";
      flake = false;
    };
  };

  outputs = { nixpkgs, nixpkgs-gcc12, agbcc, ... }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs-gcc12 { inherit system; };
          hostCompiler = pkgs.gcc12;
          armToolchain = (import nixpkgs { inherit system; }).pkgsCross.arm-embedded.stdenv.cc;
          makeWithNixShell = pkgs.writeShellScriptBin "make" ''
            exec ${pkgs.gnumake}/bin/make 'SHELL=${pkgs.bash}/bin/bash -o pipefail' "$@"
          '';
        in {
          default = (pkgs.mkShell.override { stdenv = pkgs.gcc12Stdenv; }) {
            packages = with pkgs; [
              bash
              makeWithNixShell
              git
              perl
              wget
              unzip
              python3
              pkg-config
              hostCompiler
              armToolchain
            ];

            buildInputs = with pkgs; [
              libpng
              libelf
              zlib
            ];

            # The Makefile prepends $DEVKITARM/bin while locating GCC's cc1.
            DEVKITARM = "${armToolchain}";

            # Match the native compiler in devkitpro/devkitarm (Debian Bookworm).
            CC = "${hostCompiler}/bin/gcc";
            CXX = "${hostCompiler}/bin/g++";

            # CI uses the checked-in baked game data. Match that behavior so
            # subsequent plain make runs skip the optional local QueryBaker.
            GITHUB_REPOSITORY_OWNER = "Pokabbie";

            # scaninc expects the agbcc headers at this ignored build path,
            # even when the ROM itself is built with the modern compiler.
            shellHook = ''
              # The cross compiler's setup hook also sets CC/CXX. Host tools
              # must use the native compiler after all setup hooks have run.
              export CC=${hostCompiler}/bin/gcc
              export CXX=${hostCompiler}/bin/g++
              if [ ! -e tools/agbcc/include/string.h ]; then
                mkdir -p tools/agbcc/include
                cp -R ${agbcc}/libc/include/. tools/agbcc/include/
                cp -R ${agbcc}/ginclude/. tools/agbcc/include/
              fi
            '';
          };
        });
    };
}
