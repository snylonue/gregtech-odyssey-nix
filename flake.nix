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

          server = let forge = self.packages.${system}.minecraft-forge;
          in pkgs.stdenvNoCC.mkDerivation {
            pname = "gregtech-odyssey-server";
            version = "0.0.0";
            meta.mainProgram = "server";

            dontUnpack = true;
            dontConfigure = true;

            buildPhase = ''
              mkdir -p $out/bin

              cp "${forge}/libraries/net/minecraftforge/forge/${forge.version}/unix_args.txt" "$out/bin/unix_args.txt"
            '';

            installPhase = ''
              cat <<\EOF >>$out/bin/server
              #!/usr/bin/env bash
              ${pkgs.jre_headless}/bin/java "$@" "@${
                builtins.placeholder "out"
              }/bin/unix_args.txt" nogui
              EOF

              chmod +x $out/bin/server
            '';

            fixupPhase = ''
              substituteInPlace $out/bin/unix_args.txt \
                --replace-fail "libraries" "${forge}/libraries"
            '';
          };
        };
      }) // {
        homeManagerModules.default = { config, lib, pkgs, ... }: {
          options = let inherit (lib) types mkOption;
          in {
            services.gregtech-odyssey = {
              root = mkOption { type = types.path; };

              eula = mkOption {
                type = types.bool;
                default = false;
              };
            };
          };

          config = let cfg = config.services.gregtech-odyssey;
          in {
            assertions = [{
              assertion = cfg.eula;
              message =
                "You must agree to Mojangs EULA to run minecraft-servers."
                + " Read https://account.mojang.com/documents/minecraft_eula and"
                + " set `services.minecraft-servers.eula` to `true` if you agree.";
            }];

            systemd.user.services.gregtech-odyssey = let
              inherit (lib) concatStringsSep mapAttrsToList getExe;
              gto = gregtech-odyssey;
              forge = self.packages.${pkgs.system}.minecraft-forge;
            in {
              Unit = { Description = "server of GregTech Odyssey"; };

              Install.WantedBy = [ "multi-user.target" ];

              Service = {
                ExecStartPre = let
                  symlinks = {
                    "mods" = "${gto}/.minecraft/mods";
                    "config" = "${gto}/.minecraft/config";
                    "defaultconfigs" = "${gto}/.minecraft/defaultconfigs";
                    "kubejs" = "${gto}/.minecraft/kubejs";
                    "eula.txt" = pkgs.writeText "eula.txt" "eula = true";
                  };
                  mkSymlinks = concatStringsSep "\n" (mapAttrsToList (n: v: ''
                    mkdir -p "$(dirname "${n}")"

                    ln -sf "${v}" "${n}"
                  '') symlinks);
                in getExe (pkgs.writeShellApplication {
                  name = "minecraft-server-gregtech-odyssey-start-pre";
                  text = ''
                    ${mkSymlinks}
                  '';
                });

                ExecStart = "${getExe forge} -Xmx2g";
              };
            };
          };
        };
      };
}
