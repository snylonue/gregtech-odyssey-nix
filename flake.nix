{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    gregtech-odyssey = {
      url = "gitlab:nutant233/GregTech-Odyssey";
      flake = false;
    };
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs = { self, nixpkgs, flake-utils, gregtech-odyssey, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages = {
          minecraft-forge = let
            minecraftVersion = "1.20.1";
            forgeVersion = "47.3.32";
            version = "${minecraftVersion}-${forgeVersion}";
          in pkgs.runCommandNoCC "forge-${version}" {
            inherit version;
            nativeBuildInputs = with pkgs; [ cacert curl jre_headless ];

            outputHashMode = "recursive";
            outputHash = "sha256-yuTaVeCLIngz85qSAq0EnjAFfL2sS7MeLRk58A5c2jI=";
          } ''
            mkdir -p "$out"

            curl https://maven.minecraftforge.net/net/minecraftforge/forge/${version}/forge-${version}-installer.jar -o ./installer.jar
            java -jar ./installer.jar --installServer "$out"
          '';
        };
      });
}
