{
  description = "Bridge between Nix flakes and devcontainers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems =
        [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];

      flake.flakeModule = ./flake-module.nix;

      perSystem = { pkgs, ... }: {
        devShells.default =
          pkgs.mkShell { packages = [ pkgs.nixfmt-classic ]; };
      };
    };
}
