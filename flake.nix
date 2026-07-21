{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }: let
    inherit (nixpkgs) lib;

    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];

    forAllSystems = f: lib.genAttrs systems (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          self.overlays.${system}.default
        ];
      };
    in f system pkgs);
  in {
    devShells = forAllSystems (system: pkgs: {
      default = pkgs.callPackage ./nix/shell.nix { };
    });

    packages = forAllSystems (system: pkgs: let
      src = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.difference ./. (lib.fileset.unions [
          ./.github
          ./.gitignore
          ./flake.nix
          ./flake.lock
          ./nix
        ]);
      };
    in {
      default = self.packages.${system}.heimdal;

      src = pkgs.runCommand "heimdal-src" {} "ln -s ${src} \"$out\"";

      heimdal = pkgs.callPackage ./nix/heimdal/package.nix {
        inherit src;
        inherit (pkgs.darwin.apple_sdk.frameworks) CoreFoundation Security SystemConfiguration;
        autoreconfHook = pkgs.buildPackages.autoreconfHook271;
      };

      nixosTest = pkgs.testers.runNixOSTest (import ./nix/nixosTest.nix { inherit nixpkgs; });
    });

    overlays = forAllSystems (system: pkgs: {
      default = final: prev: {
        heimdal = self.packages.${system}.heimdal;
      };
    });

    nixosModules = {
      default = self.nixosModules.heimdal;
      heimdal = ./nix/module;
    };
  };
}
