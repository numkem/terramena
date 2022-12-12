{
  description = "Use colmena to provision instances created by Terraform";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        devPackages = [
          pkgs.rubyPackages_3_1.solargraph
          pkgs.rubyPackages_3_1.rspec
          pkgs.rubyPackages_3_1.rake
        ];

        rubyWithGems = pkgs.ruby_3_1.withPackages (ps: with ps; [ slop ]);
      in {
        packages = flake-utils.lib.flattenTree {
          default = pkgs.stdenv.mkDerivation {
            name = "terramena";
            src = self;
            buildInputs = [ rubyWithGems ];

            installPhase = ''
              mkdir -p $out/lib $out/bin $out/share
              cp bin/* $out/bin/
              cp lib/* $out/lib/
              cp share/* $out/share/
            '';
          };
        };

        devShells.default =
          pkgs.mkShell { buildInputs = [ rubyWithGems ] ++ devPackages; };
      });
}
