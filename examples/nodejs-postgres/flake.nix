{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-devcontainer.url = "github:nix-modules/nix-devcontainer";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [ inputs.nix-devcontainer.flakeModule ];
    systems = [ "x86_64-linux" "aarch64-darwin" ];

    perSystem = { pkgs, ... }: {
      nix-devcontainer = {
        enable = true;
        file = toString ./.devcontainer/devcontainer.json;
        packages = [ pkgs.nodejs_20 pkgs.postgresql pkgs.redis ];
        # localEnv.SOME_SECRET = "...";  # optional, for local-only vars
      };
    };
  };
}
