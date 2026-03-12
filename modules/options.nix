{ lib, ... }: {
  perSystem = { ... }: {
    options.nix-devcontainer = {
      enable = lib.mkEnableOption "nix-devcontainer devcontainer bridge";

      file = lib.mkOption {
        type = lib.types.path;
        default = ./.devcontainer/devcontainer.json;
        description = ''
          Path to devcontainer.json. Resolved at eval time.
          The dockerComposeFile field inside it is resolved relative to this file's directory.
        '';
      };

      packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = ''
          Packages for the local nix shell. Should mirror what the devcontainer
          gets via ghcr.io/devcontainers/features/nix:1 pointing at this flake.
        '';
      };

      localEnv = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Extra environment variables for the local shell only (not in container).
          Useful for secrets, machine-specific overrides, or anything that should
          not live in devcontainer.json or docker-compose.yml.
        '';
      };
    };
  };
}
