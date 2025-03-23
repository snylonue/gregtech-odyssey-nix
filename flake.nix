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
            forgeVersion = "47.4.0";
            version = "${minecraftVersion}-${forgeVersion}";
          in pkgs.runCommandNoCC "forge-${version}" {
            inherit version;
            nativeBuildInputs = with pkgs; [ cacert curl jre_headless ];

            outputHashMode = "recursive";
            outputHash = "sha256-EtqyOX9REjT5sCxm2s+dhSzXnIvuFEhdFqlwgVbEugw=";
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

              ops = mkOption {
                type = types.listOf (types.submodule {
                  options = {
                    uuid = mkOption { type = types.str; };
                    name = mkOption { type = types.str; };
                    level = mkOption {
                      type = types.int;
                      default = 4;
                    };
                  };
                });
                default = [ ];
              };

              maxMemory = mkOption {
                type = types.str;
                default = "2G";
              };

              minMemory = mkOption { type = types.str; };

              extraJavaArgs = mkOption {
                type = types.str;
                default = "";
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

              Install.WantedBy = [ "default.target" ];

              Service = {
                WorkingDirectory = cfg.root;

                ExecStartPre = let
                  listServerMods = dir:
                    lib.flatten (lib.mapAttrsToList (name: type:
                      if type == "directory"
                      || lib.strings.hasPrefix "jecharacters" name then
                        [ ]
                      else
                        [ name ]) (builtins.readDir dir));
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
                    "kubejs" = "${gto}/.minecraft/kubejs";
                    "eula.txt" = pkgs.writeText "eula.txt" "eula = true";
                    "ops.json" =
                      pkgs.writeText "ops.json" (builtins.toJSON cfg.ops);
                  } // builtins.listToAttrs (map (mod: {
                    name = "mods/${mod}";
                    value = "${gto}/.minecraft/mods/${mod}";
                  }) (listServerMods "${gto}/.minecraft/mods"));
                  mkSymlinks = concatStringsSep "\n" (mapAttrsToList (n: v: ''
                    mkdir -p "$(dirname "${n}")"

                    ln -sf "${v}" "${n}"

                    ${markManaged n}
                  '') symlinks);
                  # copy config to working directory since it will be written to at runtime
                  # defaultconfigs is copied too to make sure config files have write permissions
                  patchConfig = ''
                    cp -r "${gto}/.minecraft/config" .
                    chmod +w -R config/
                    ${markManaged "config"}

                    cp -r "${gto}/.minecraft/defaultconfigs" .
                    chmod +w -R defaultconfigs
                    ${markManaged "defaultconfigs"}
                  '';
                in getExe (pkgs.writeShellApplication {
                  name = "minecraft-server-gregtech-odyssey-start-pre";
                  text = ''
                    ${cleanAllManaged}
                    ${mkSymlinks}
                    ${patchConfig}
                  '';
                  runtimeInputs = with pkgs; [ coreutils ];
                });

                ExecStart = let
                  args = (lib.optionalString (cfg.maxMemory != null)
                    "-Xmx${cfg.maxMemory} ")
                    + (lib.optionalString (cfg.minMemory != null)
                      "-Xms{cfg.minMemory} ") + cfg.extraJavaArgs;
                in "${getExe server} ${args}";
              };
            };
          };
        };
      };
}
