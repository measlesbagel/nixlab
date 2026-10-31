# A host's real configuration as a disposable QEMU VM on its disko layout,
# with the verification scaffolding below layered on top. Never deployed.
#   nix build --impure --file vm.nix --argstr flake "$PWD" --argstr host seladonia
{
  flake,
  host ? "seladonia",
}:
let
  # A git flake: untracked files are invisible until `git add`.
  self = builtins.getFlake flake;
  base = self.nixosConfigurations.${host};

  scaffolding =
    { lib, ... }:
    {
      # disko builds vmWithDisko from the top-level config, not from the
      # host's vmVariant, so its settings are repeated here.
      users.users.root.initialPassword = "vm";
      systemd.services.deploy-watchdog.wantedBy = lib.mkForce [ ];
      systemd.paths.deploy-rollback.wantedBy = lib.mkForce [ ];
      # Would pull main and switch the VM away from the build under test.
      services.comin.enable = lib.mkForce false;

      virtualisation.vmVariantWithDisko.virtualisation = {
        graphics = false;
        memorySize = 4096;
        cores = 4;
        # slirp otherwise reaches the real LAN (albipes NFS, RustFS) and the internet.
        restrictNetwork = true;
      };
    };

  vm = (base.extendModules { modules = [ scaffolding ]; }).config.virtualisation.vmVariantWithDisko;
in
vm.system.build.vmWithDisko
// {
  inherit (vm.system.build) toplevel;
}
