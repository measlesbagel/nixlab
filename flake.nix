{
  description = "nixlab — bare-metal NixOS homelab monorepo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    opnix.url = "github:brizzbuzz/opnix";
    opnix.inputs.nixpkgs.follows = "nixpkgs";

    # hjem-rum is tested against its own pinned hjem, so hjem follows it.
    hjem-rum.url = "github:snugnug/hjem-rum";
    hjem-rum.inputs.nixpkgs.follows = "nixpkgs";
    hjem.follows = "hjem-rum/hjem";

    nix-rtl8159.url = "github:measlesbagel/nix-rtl8159";
    nix-rtl8159.inputs.nixpkgs.follows = "nixpkgs";

    comin.url = "github:nlewo/comin";
    comin.inputs.nixpkgs.follows = "nixpkgs";

    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";

    nixos-images.url = "github:nix-community/nixos-images";
    nixos-images.inputs.nixos-unstable.follows = "nixpkgs";
    nixos-images.inputs.nixos-stable.follows = "nixpkgs";

    # Keeps its own nixpkgs: the Sparks take their kernel and NVIDIA driver
    # from it (modules/spark.nix), as upstream's full builds cache them.
    nixos-dgx-spark.url = "github:graham33/nixos-dgx-spark";
    nixos-dgx-spark.inputs.disko.follows = "disko";
    nixos-dgx-spark.inputs.flake-parts.follows = "flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { ... }:
      let
        lib = inputs.nixpkgs.lib;

        commonModules = [
          ./modules/topology.nix
          ./modules/base.nix
          ./modules/lan.nix
          ./modules/ssh.nix
          ./modules/opnix.nix
          ./modules/backup.nix
          ./modules/snapshots.nix
          ./modules/replication.nix
          ./modules/watchdog.nix
          ./modules/reboot.nix
          ./modules/ups.nix
          ./modules/cache.nix
          ./modules/comin.nix
        ];

        # `system` also picks the CI runner that builds the host.
        hosts = {
          seladonia = {
            system = "x86_64-linux";
            dir = ./hosts/seladonia;
            modules = [
              ./modules/zfs.nix
              ./services/caddy.nix
              ./services/ddns.nix
              ./services/pocket-id.nix
              ./services/wireguard.nix
              ./services/dns.nix
              ./services/attic-public.nix
              ./services/postgresql.nix
              ./services/navidrome.nix
              ./services/model-sync.nix
            ];
          };
          albipes = {
            system = "x86_64-linux";
            dir = ./hosts/albipes;
            modules = [
              ./modules/zfs.nix
              ./services/smartd.nix
              ./services/zfs-replication.nix
              ./services/attic.nix
              ./services/rustfs.nix
              ./services/model-library.nix
              ./services/music-share.nix
            ];
          };
          chilense = {
            system = "x86_64-linux";
            dir = ./hosts/chilense;
            modules = [
              ./modules/zfs.nix
              inputs.hjem.nixosModules.default
              inputs.nix-rtl8159.nixosModules.default
              ./services/model-sync.nix
            ];
          };
          leetzi = {
            system = "aarch64-linux";
            dir = ./hosts/leetzi;
            modules = [
              ./modules/spark.nix
              ./modules/remote-builder.nix
              ./services/model-sync.nix
            ];
          };
          elegans = {
            system = "aarch64-linux";
            dir = ./hosts/elegans;
            modules = [
              ./modules/spark.nix
              ./modules/remote-builder.nix
              ./services/model-sync.nix
            ];
          };
        };

        # colmena's eval-config.nix skips lib.nixosSystem's version stamp.
        nixpkgsVersion = {
          system.nixos.versionSuffix = ".${
            lib.substring 0 8 inputs.nixpkgs.lastModifiedDate
          }.${inputs.nixpkgs.shortRev}";
          system.nixos.revision = inputs.nixpkgs.rev;
        };

        hostModules =
          spec:
          commonModules
          ++ [
            nixpkgsVersion
            spec.dir
          ]
          ++ spec.modules;

        inherit ((lib.evalModules { modules = [ ./modules/topology.nix ]; }).config.homelab) nodes lan;

        # Pinned keys are checked; a host with none yet is trusted on first use.
        knownHosts = builtins.toFile "nixlab-known-hosts" (
          lib.concatStrings (
            lib.mapAttrsToList (name: node: "${name},${name}.${lan.domain},${node.ip} ${node.sshHostKey}\n") (
              lib.filterAttrs (_: node: node.sshHostKey != null) nodes
            )
          )
        );
      in
      {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];

        flake = {
          # One evaluation: CI builds exactly the system comin and colmena deploy.
          nixosConfigurations = inputs.self.colmenaHive.nodes;

          colmenaHive = inputs.colmena.lib.makeHive (
            {
              meta = {
                nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
                nodeNixpkgs = lib.mapAttrs (_: spec: import inputs.nixpkgs { inherit (spec) system; }) hosts;
                specialArgs = { inherit inputs; };
              };
            }
            // lib.mapAttrs (name: spec: {
              deployment = {
                targetUser = "deploy";
                tags = [
                  "homelab"
                  nodes.${name}.genus
                ];
                # As comin does: the host builds, pulling what it can from Attic.
                buildOnTarget = true;
                # Resolved by /etc/hosts (modules/lan.nix) or, over WireGuard,
                # services/dns.nix.
                targetHost = "${name}.${lan.domain}";
                # One file per option: colmena hands these to `nix copy` in
                # NIX_SSHOPTS, which splits on spaces.
                sshOptions = [
                  "-o"
                  "GlobalKnownHostsFile=${knownHosts}"
                  "-o"
                  "StrictHostKeyChecking=accept-new"
                ];
              };
              imports = hostModules spec;
            }) hosts
          );

        };

        perSystem =
          { system, config, ... }:
          let
            pkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          in
          {
            formatter = pkgs.nixfmt-tree;

            checks =
              let
                lint =
                  name: tool: cmd:
                  pkgs.runCommand name { nativeBuildInputs = [ tool ]; } ''
                    cp -r ${./.} src
                    cd src
                    ${cmd}
                    touch $out
                  '';
              in
              {
                statix = lint "statix" pkgs.statix "statix check .";
                deadnix = lint "deadnix" pkgs.deadnix "deadnix --fail .";
              }
              # Evaluates every host, so once is enough.
              // lib.optionalAttrs (system == "x86_64-linux") {
                access-policy = import ./tests/access-policy.nix {
                  inherit lib pkgs;
                  inherit (inputs.self) nixosConfigurations;
                };
              };

            packages.kexec-installer =
              (lib.nixosSystem {
                inherit system;
                modules = [
                  inputs.nixos-images.nixosModules.kexec-installer
                  ./installer
                ];
              }).config.system.build.kexecInstallerTarball;

            packages.provision = pkgs.writeShellApplication {
              name = "provision";
              runtimeInputs = [
                pkgs.nixos-anywhere
                pkgs.openssh
                pkgs.jq
              ];
              # `op` comes from the host, for 1Password's desktop integration.
              text =
                lib.replaceStrings
                  [ "@nodes@" "@flake@" ]
                  [
                    (builtins.toJSON (
                      lib.mapAttrs (name: spec: {
                        inherit (spec) system;
                        inherit (inputs.self.nixosConfigurations.${name}.config.homelab.nodes.${name})
                          ip
                          bootstrapTarget
                          ;
                      }) hosts
                    ))
                    "${inputs.self}"
                  ]
                  (builtins.readFile ./scripts/provision.sh);
            };
            apps.provision.program = lib.getExe config.packages.provision;

            packages.deploy = pkgs.writeShellApplication {
              name = "deploy";
              runtimeInputs = [
                pkgs.colmena
                pkgs.openssh
              ];
              text = ''
                if [ "$#" -eq 0 ]; then
                  set -- ${lib.concatStringsSep " " (lib.attrNames hosts)}
                fi

                on=$(IFS=,; echo "$*")
                colmena apply --on "$on"
                colmena exec --on "$on" -- sudo deploy-confirm
              '';
            };
            # Compares committed HEAD only; uncommitted edits are ignored.
            packages.changed-hosts = pkgs.writeShellApplication {
              name = "changed-hosts";
              runtimeInputs = [
                pkgs.git
                pkgs.jq
                pkgs.nix
              ];
              text = ''
                base=$(git rev-parse "''${1:?usage: changed-hosts <base-rev>}")
                head=$(git rev-parse HEAD)

                # Both sides through the same git fetcher, so identical trees
                # give identical drvs.
                drv() { nix eval --raw "git+file://$PWD?rev=$1#nixosConfigurations.$2.config.system.build.toplevel.drvPath"; }

                changed=()
                for host in ${lib.concatStringsSep " " (lib.attrNames hosts)}; do
                  new=$(drv "$head" "$host")
                  old=$(drv "$base" "$host" 2> /dev/null || echo none)
                  if [ "$new" != "$old" ]; then
                    changed+=("$host")
                  fi
                done

                jq -cn --argjson systems '${builtins.toJSON (lib.mapAttrs (_: spec: spec.system) hosts)}' \
                  '$ARGS.positional | map({host: ., system: $systems[.]})' --args "''${changed[@]}"
              '';
            };

            apps.deploy.program = lib.getExe config.packages.deploy;

            devShells.default = pkgs.mkShell {
              packages = [
                pkgs.colmena
                pkgs.nixos-anywhere
                pkgs.attic-client
                inputs.opnix.packages.${system}.default
                pkgs._1password-cli
                pkgs.restic
              ];
            };
          };
      }
    );
}
