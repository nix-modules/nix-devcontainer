_: {
  perSystem =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      opts = config.nix-devcontainer;
      # localEnv exported at eval time — local-only secrets/overrides not in devcontainer.json
      localEnvExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") opts.localEnv
      );
    in
    lib.mkIf opts.enable {
      devShells.default = pkgs.mkShell {
        # User packages + bridge script added to PATH
        packages = opts.packages ++ [ config.packages.nix-devcontainer ];

        shellHook = ''
          # Export local-only vars (secrets, machine-specific overrides)
          ${localEnvExports}

          # Run the bridge script — starts services, discovers ports, rewrites and exports
          # containerEnv vars from devcontainer.json (service:port → localhost:hostPort)
          eval "$(nix-devcontainer ${lib.escapeShellArg opts.file})"

          echo "[nix-devcontainer] Environment ready"
        '';
      };

    };
}
