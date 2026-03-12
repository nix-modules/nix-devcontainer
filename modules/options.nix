{ lib, ... }: {
  perSystem = { ... }: {
    options.nix-devcontainer = {
      enable = lib.mkEnableOption "nix-devcontainer devcontainer bridge";

      file = lib.mkOption {
        type = lib.types.str;
        description = ''
          Absolute path to devcontainer.json as a string.
          Use toString to prevent Nix from copying it to the store:

            file = toString ./.devcontainer/devcontainer.json;

          The dockerComposeFile field inside it is resolved relative to
          this file's directory on the actual filesystem.
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
