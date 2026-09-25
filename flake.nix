{
  description = "Delta, Zed's standalone AI coding agent, packaged for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    lib = nixpkgs.lib;
    systems = builtins.attrNames (lib.importJSON ./sources.json).hashes;
    forAllSystems = f:
      lib.genAttrs systems (system:
        f (import nixpkgs {
          inherit system;
          # Delta is proprietary. Allowing it here only affects this flake's own
          # packages/apps; the overlay follows whatever the consumer's nixpkgs
          # config says.
          config.allowUnfreePredicate = pkg: lib.getName pkg == "delta";
        }));
  in {
    # `zed-delta`, not `delta`: nixpkgs' `delta` is git-delta, and shadowing it
    # would swap the diff pager out from under every consumer.
    overlays.default = final: _prev: {
      zed-delta = final.callPackage ./package.nix {};
    };

    packages = forAllSystems (pkgs: {
      delta = pkgs.callPackage ./package.nix {};
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.delta;
    });

    apps = forAllSystems (pkgs: {
      update = {
        type = "app";
        program = lib.getExe (pkgs.writeShellApplication {
          name = "update";
          runtimeInputs = [pkgs.curl pkgs.jq pkgs.nix];
          text = builtins.readFile ./update.sh;
        });
      };
    });

    # Bare `nix fmt` passes no paths, and alejandra then waits on stdin.
    formatter =
      forAllSystems (pkgs:
        pkgs.writeShellScriptBin "fmt" ''exec ${lib.getExe pkgs.alejandra} "''${@:-.}"'');
  };
}
