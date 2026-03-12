{ lib, config, pkgs, ... }:
let
  cfg = config.nix-devcontainer;

  # localEnv exported at eval time — local-only secrets/overrides not in devcontainer.json
  localEnvExports = lib.concatStringsSep "\n"
    (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}")
      cfg.localEnv);
in lib.mkIf cfg.enable {

  devShells.default = pkgs.mkShell {
    # User packages + bridge script added to PATH
    packages = cfg.packages ++ [ config.packages.nix-devcontainer-bridge ];

    shellHook = ''
      # Export local-only vars (secrets, machine-specific overrides)
      ${localEnvExports}

      # Run the bridge script — starts services, discovers ports, rewrites and exports
      # containerEnv vars from devcontainer.json (service:port → localhost:hostPort)
      source "$(command -v nix-devcontainer-bridge)"

      echo "[nix-devcontainer] Environment ready"
    '';
  };

}
