{ ... }:
{
  perSystem = { lib, config, pkgs, ... }:
    let cfg = config.nix-devcontainer;
    in lib.mkIf cfg.enable {

      # Wrap scripts/compose.sh into a nix package.
      # DEVCONTAINER_JSON path is baked in at eval time — no runtime path lookup needed.
      # pkgs.writeShellApplication runs shellcheck and sets strict shell options automatically.
      packages.nix-devcontainer-bridge = pkgs.writeShellApplication {
        name = "nix-devcontainer-bridge";
        runtimeInputs = [ pkgs.docker pkgs.jq ];
        text = ''
          DEVCONTAINER_JSON="${cfg.file}"
          ${builtins.readFile ../scripts/compose.sh}
        '';
      };

    };
}
