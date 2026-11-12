# Boot test: disko's installTest formats scratch disks from the host's disko
# layout, installs the bootloader on them and boots the host's configuration
# in QEMU, where the checks below run. CI runs it for each changed `vmTest`
# host (flake.nix):
#   nix build .#nixosConfigurations.<host>.config.system.build.installTest -L
# The VM has 1 GiB of RAM, fixed by disko, and no OpNix token. comin and the
# LAN clients run in it as on the host; the build sandbox keeps them offline.
{
  config,
  lib,
  utils,
  ...
}:
let
  cfg = config.homelab.vmTest;

  secretUnits = lib.concatMap (secret: secret.services) (
    lib.attrValues config.services.onepassword-secrets.secrets
  );

  nfsPaths = map (fs: fs.mountPoint) (
    lib.filter (
      fs:
      lib.elem fs.fsType [
        "nfs"
        "nfs4"
      ]
    ) (lib.attrValues config.fileSystems)
  );
  onNfs = path: lib.any (nfs: path == nfs || lib.hasPrefix "${nfs}/" path) nfsPaths;
  # systemd skips these when the mount fails; they never start, so never fail.
  nfsServices = lib.attrNames (
    lib.filterAttrs (
      _: service: lib.any onNfs (lib.toList (service.unitConfig.RequiresMountsFor or [ ]))
    ) config.systemd.services
  );

  preamble = ''
    import json
    from datetime import timedelta
    from shlex import quote

    machine.wait_for_unit("multi-user.target")
    # disko's QEMU falls back to emulation without KVM, too slow to trust.
    machine.succeed('[ "$(systemd-detect-virt)" = kvm ]')
    # Timers follow the wall clock; a check starts what it tests.
    machine.succeed("systemctl stop '*.timer'")
  '';

  gate = ''
    with subtest("only units the VM cannot run failed, restarted or were skipped"):
        unverifiable: dict[str, str] = ${builtins.toJSON cfg.unverifiable}
        seen: dict[str, set[str]] = {}

        # A unit that is still starting has not failed yet.
        _, state = machine.execute("systemctl is-system-running --wait", timeout=timedelta(minutes=2))
        assert state.strip() in ["running", "degraded"], "the boot did not finish:\n" + machine.succeed("systemctl list-jobs")

        states = "failed,auto-restart,auto-restart-queued"
        for unit in machine.succeed(f"systemctl list-units --all --plain --no-legend --state={states}").splitlines():
            seen.setdefault(unit.split()[0], set()).add(unit.split()[3])

        # A crash loop looks healthy between two restarts. journald comes over
        # from the initrd, which systemd counts as one.
        expected_restarts = {"systemd-journald.service": 1}
        for block in machine.succeed("systemctl show --all '*.service' -p Id,NRestarts").strip().split("\n\n"):
            service = dict(line.split("=", 1) for line in block.splitlines())
            restarts = int(service["NRestarts"])
            if restarts > expected_restarts.get(service["Id"], 0):
                seen.setdefault(service["Id"], set()).add(f"restarted {restarts} times")

        # A unit skipped because a dependency failed stays inactive, and one
        # that failed may have been started again since. The journal has both.
        machine.succeed('[ -n "$(journalctl -b -q -n 1 _PID=1 JOB_RESULT=done)" ]')
        results = " ".join(f"JOB_RESULT={result}" for result in ["failed", "dependency", "timeout", "assert"])
        for line in machine.succeed(f"journalctl -b -q -o json --output-fields=UNIT,JOB_RESULT _PID=1 {results}").splitlines():
            entry = json.loads(line)
            seen.setdefault(entry["UNIT"], set()).add(f"job result {entry['JOB_RESULT']}")

        for unit, reason in sorted(unverifiable.items()):
            observed = ", ".join(sorted(seen.get(unit, set())))
            print(f"not verified: {unit} ({reason})" + (f": {observed}" if observed else ""))
        unexpected = sorted(set(seen) - set(unverifiable))
        for unit in unexpected:
            print(machine.execute(f"systemctl status --no-pager --lines=30 {quote(unit)}")[1])
        assert not unexpected, "; ".join(f"{unit}: {', '.join(sorted(seen[unit]))}" for unit in unexpected)
  '';
in
{
  options.homelab.vmTest = {
    checks = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = { };
      description = ''
        Test-driver Python run against the booted host as `machine`, in name
        order, each named for what it checks and holding its own
        `with subtest(...)`. `json`, `quote` and `timedelta` are imported.
      '';
    };
    unverifiable = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "smartd.service" = "QEMU disks have no SMART data";
      };
      description = ''
        Units that cannot work in the VM, each with the reason. Only these may
        fail, restart or be skipped there, so nothing about them is tested.
      '';
    };
  };

  config = {
    homelab.vmTest.unverifiable =
      lib.genAttrs (map (unit: "${unit}.service") secretUnits) (_: "needs a 1Password secret")
      // lib.genAttrs (map (path: "${utils.escapeSystemdPath path}.mount") nfsPaths) (
        _: "needs the NFS server on the LAN"
      )
      // lib.genAttrs (map (service: "${service}.service") nfsServices) (_: "needs an NFS mount");

    disko.tests.extraChecks = lib.concatLines ([ preamble ] ++ lib.attrValues cfg.checks ++ [ gate ]);
  };
}
