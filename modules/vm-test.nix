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
        with subtest("only units the VM cannot run have failed or are restarting"):
            from datetime import timedelta

            unverifiable = ${builtins.toJSON unverifiable}
            down = set()

            def stuck():
                units = machine.succeed("systemctl list-units --state=failed,auto-restart --plain --no-legend | cut -d' ' -f1").split()
                down.update(units)
                return [unit for unit in units if unit not in unverifiable]

            def restarts():
                blocks = machine.succeed("systemctl show '*.service' -p Id,NRestarts").split("\n\n")
                units = [dict(line.split("=", 1) for line in block.splitlines()) for block in blocks if block.strip()]
                return {unit["Id"]: int(unit["NRestarts"]) for unit in units}

            machine.execute("systemctl is-system-running --wait", timeout=timedelta(minutes=2))
            # A unit that failed once early may still be waiting out RestartSec.
            for _ in range(60):
                unexpected = stuck()
                if not unexpected:
                    break
                machine.sleep(duration=timedelta(seconds=1))

            # A crash loop looks clean between restarts, and can keep step with
            # the polling, so its restart count is watched too.
            before = restarts()
            for _ in range(15):
                machine.sleep(duration=timedelta(seconds=1))
                unexpected += stuck()
            churn = [unit for unit, count in restarts().items() if unit not in unverifiable and count > before.get(unit, 0)]

            for unit, reason in sorted(unverifiable.items()):
                print(f"not verified: {unit} ({reason}){', failed or restarting' if unit in down else '''}")
            problems = []
            if unexpected:
                problems.append(f"failed or restarting: {' '.join(sorted(set(unexpected)))}")
            if churn:
                problems.append(f"restarted after the boot settled: {' '.join(churn)}")
            assert not problems, "; ".join(problems)
      '')
    ];
  };
}
