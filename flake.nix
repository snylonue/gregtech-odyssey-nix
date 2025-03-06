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
              #!${pkgs.lib.getExe pkgs.bash}
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
              enable = mkOption {
                type = types.bool;
                default = false;
              };

              root = mkOption { type = types.path; };

              eula = mkOption {
                type = types.bool;
                default = false;
              };
            };
          };

          config = let cfg = config.services.gregtech-odyssey;
          in lib.mkIf cfg.enable {
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
              server = self.packages.${pkgs.system}.server;
            in {
              Unit = { Description = "server of GregTech Odyssey"; };

              Install.WantedBy = [ "multi-user.target" ];

              Service = {
                WorkingDirectory = cfg.root;

                ExecStartPre = let
                  markManaged = file:
                    ''echo "${file}" >> .nix-minecraft-managed'';
                  cleanAllManaged = ''
                    if [ -e .nix-minecraft-managed ]; then
                      readarray -t to_delete < .nix-minecraft-managed
                      rm -rf "''${to_delete[@]}"
                      rm .nix-minecraft-managed
                    fi
                  '';
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

                    ${markManaged n}
                  '') symlinks);
                in getExe (pkgs.writeShellApplication {
                  name = "minecraft-server-gregtech-odyssey-start-pre";
                  text = ''
                    ${cleanAllManaged}
                    ${mkSymlinks}
                  '';
                  runtimeInputs = with pkgs; [ coreutils ];
                });

                ExecStart = "${getExe server} -Xmx2g";
              };
            };
          };
        };
      };
}
