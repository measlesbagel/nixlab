# The host's own system, installed onto scratch disks from its disko layout and
# booted in QEMU by disko's installTest, which then runs the checks that owning
# modules append to disko.tests.extraChecks:
#   nix build .#nixosConfigurations.<host>.config.system.build.installTest -L
{
  config,
  lib,
  utils,
  ...
}:
let
  inherit (config.homelab.vmTest) unverifiable;

  # The VM has no OpNix token and no LAN.
  secretUnits = lib.concatMap (secret: secret.services) (
    lib.attrValues config.services.onepassword-secrets.secrets
  );
  nfsMounts = lib.attrNames (lib.filterAttrs (_: fs: fs.fsType == "nfs") config.fileSystems);
in
{
  options.homelab.vmTest.unverifiable = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "Units that cannot work in the VM test, each with the reason. Only these may fail there.";
  };

  config = {
    homelab.vmTest.unverifiable =
      lib.genAttrs (map (unit: "${unit}.service") secretUnits) (_: "needs a 1Password secret")
      // lib.genAttrs (map (path: "${utils.escapeSystemdPath path}.mount") nfsMounts) (
        _: "needs the NFS server on the LAN"
      );

    disko.tests.extraChecks = lib.mkMerge [
      (lib.mkBefore ''
        machine.wait_for_unit("multi-user.target")
        # disko's qemu falls back to emulation without KVM, too slow to trust.
        machine.succeed('[ "$(systemd-detect-virt)" = kvm ]')
      '')
      (lib.mkAfter ''
        with subtest("only units the VM cannot run have failed"):
            unverifiable = ${builtins.toJSON unverifiable}
            failed = machine.succeed("systemctl list-units --failed --plain --no-legend | cut -d' ' -f1").split()
            for unit, reason in sorted(unverifiable.items()):
                print(f"not verified: {unit} ({reason}){', failed' if unit in failed else '''}")
            unexpected = [unit for unit in failed if unit not in unverifiable]
            assert not unexpected, f"failed: {' '.join(unexpected)}"
      '')
    ];
  };
}
