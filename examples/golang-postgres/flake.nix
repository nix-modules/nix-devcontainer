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
        file = ./.devcontainer/devcontainer.json;
        packages = [
          pkgs.go
          pkgs.gopls
          pkgs.gotools           # goimports, godoc, etc.
          pkgs.golangci-lint
          pkgs.postgresql        # psql, pg_dump, pg_restore
          pkgs.golang-migrate    # migrate -database $DATABASE_URL -path ./migrations up
        ];
        # localEnv.DATABASE_URL = "..."; # optional override
      };
    };
  };
}
