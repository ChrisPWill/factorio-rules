{
  description = "Factorio Rules development tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      toolsFor = pkgs: with pkgs; [
        actionlint
        gnumake
        lua5_2
        lua52Packages.luacheck
        python3
        stylua
      ];
    in {
      devShells = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.mkShell {
            packages = toolsFor pkgs;
          };
        });

      packages = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.runCommand "factorio-rules-package" {
            nativeBuildInputs = toolsFor pkgs;
            src = self;
          } ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            make check
            make package
            mkdir -p "$out"
            cp dist/*.zip "$out/"
          '';
        });

      checks = forAllSystems (system: {
        package = self.packages.${system}.default;
      });
    };
}
