{
  description = "www.tdude.co";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.hugo-theme-hyde-hyde = {
    url = "github:htr3n/hyde-hyde";
    flake = false;
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, hugo-theme-hyde-hyde }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      perSystem = { pkgs, ... }: {
        packages.tdude-website = pkgs.stdenv.mkDerivation {
          name = "www.tdude.co";
          src = ./.;
          buildPhase = ''
            mkdir -p themes
            ln -s ${hugo-theme-hyde-hyde} themes/hyde-hyde
            ${pkgs.hugo}/bin/hugo --minify
          '';
          installPhase = ''
            cp -r public $out
          '';
          meta = with pkgs.lib; {
            description = "Things I consider interesting";
            license = licenses.mit;
            platforms = platforms.unix;
            maintainers = with maintainers; [ starcraft66 ];
          };
        };
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [ pkgs.hugo ];
          buildInputs = [ ];
        };
      };
    };
}
