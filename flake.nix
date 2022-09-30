{
  description = "Use colmena to provision instances created by Terraform";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages = flake-utils.lib.flattenTree {
          default = pkgs.stdenv.mkDerivation {
            name = "terramena";
            src = self;
            buildInputs = with pkgs; [ ruby_3_1 ];

            installPhase = ''
              mkdir -p $out/lib $out/bin
              cp bin/* $out/bin/
              cp lib/* $out/lib/
            '';
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            ruby_3_1
            bundix
          ];
        };
      });
}
