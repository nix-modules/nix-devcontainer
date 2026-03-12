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
    in
    lib.mkIf opts.enable {
      # Wrap scripts/nix-devcontainer.sh into a nix package.
      # pkgs.writeShellApplication runs shellcheck and sets strict shell options automatically.
      packages.nix-devcontainer = pkgs.writeShellApplication {
        name = "nix-devcontainer";
        runtimeInputs = [
          pkgs.docker
          pkgs.jq
          pkgs.yq-go
        ];
        text = builtins.readFile ../scripts/nix-devcontainer.sh;
      };
    };
}
