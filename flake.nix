{
  description = "Mindustry (self-maintained) flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            self.overlays.default
          ];
        };
      in
      {
        packages = {
          default = pkgs.mindustry;
          mindustry = pkgs.mindustry;

          mindustry-server = pkgs.mindustry.override {
            enableClient = false;
            enableServer = true;
          };
          mindustry-client = pkgs.mindustry.override {
            enableClient = true;
            enableServer = false;
          };
          mindustry-wayland = pkgs.mindustry.override { enableWayland = true; };
        };

        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.mindustry;
          exePath = "/bin/mindustry";
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nixfmt-rfc-style
            pkgs.nixpkgs-fmt
            pkgs.nurl
          ];
        };
      }
    )
    // {
      overlays.default = final: prev: {
        mindustry = final.callPackage ./pkgs/mindustry/package.nix { };
      };
    };
}
