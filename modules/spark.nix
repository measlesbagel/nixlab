# GB10 boxes: github:graham33/nixos-dgx-spark, plus what DGX OS ships that it
# lacks and recovery from hangs.
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # Built by upstream's own nixpkgs, as its full builds push it to
  # graham33.cachix.org; the rest of the system stays on ours.
  upstreamKernel = inputs.nixos-dgx-spark.nixosConfigurations.dgx-spark.config.boot.kernelPackages;

  # In a memory-pressure livelock PID 1 still pets RuntimeWatchdogSec, so this
  # pets the hardware watchdog only while fork/exec still works.
  hangWatchdog = pkgs.writeShellApplication {
    name = "hang-watchdog";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      exec 3> /dev/watchdog0
      # Magic close: a clean stop disarms rather than resets (nowayout is 0).
      trap 'printf V >&3; exit 0' TERM INT

      failures=0
      while true; do
        # External binaries on purpose: the probe must fork and exec.
        if timeout 10 ${pkgs.coreutils}/bin/true; then
          failures=0
          printf k >&3
        else
          failures=$((failures + 1))
          echo "fork/exec probe failed ($failures)"
        fi
        sleep 15
      done
    '';
  };
in
{
  imports = [ inputs.nixos-dgx-spark.nixosModules.dgx-spark ];

  hardware.dgx-spark.enable = true;
  # The module enables it unconditionally.
  services.dgx-dashboard.enable = lib.mkForce false;

  # The NVIDIA driver comes from this set too.
  boot.kernelPackages = lib.mkForce upstreamKernel;
  # The driver's libraries load into our processes, which cannot provide
  # symbols from a newer glibc.
  assertions = [
    {
      assertion = lib.versionAtLeast pkgs.glibc.version upstreamKernel.stdenv.cc.libc.version;
      message = "nixos-dgx-spark's nixpkgs has glibc ${upstreamKernel.stdenv.cc.libc.version}, newer than ours (${pkgs.glibc.version}): update nixpkgs too.";
    }
  ];

  # Upstream's full builds push the kernel, its modules and the driver here.
  # Until one has run for upstream's current kernel, the Spark compiles it.
  # The module adds Flox.
  nix.settings = {
    extra-substituters = [ "https://graham33.cachix.org" ];
    extra-trusted-public-keys = [
      "graham33.cachix.org-1:DqH72VpwSrACa3+L9eqh4bixjWx9IQUaxQtRh4gtkX8="
    ];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # As DGX OS boots.
  boot.kernelParams = [ "init_on_alloc=0" ];

  # action=1 panics on the first stage; the timeout must outlast several of the
  # probe's 15 s rounds.
  boot.kernelModules = [ "sbsa_gwdt" ];
  boot.extraModprobeConfig = "options sbsa_gwdt action=1 timeout=60";

  systemd.services.hang-watchdog = {
    description = "Pet the hardware watchdog while fork/exec still works";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = lib.getExe hangWatchdog;
      OOMScoreAdjust = -1000;
    };
  };

  security.pam.loginLimits = [
    {
      domain = "*";
      type = "-";
      item = "nofile";
      value = "500000";
    }
  ];
  boot.kernel.sysctl = {
    # Three NICs on three subnets: ARP only from the one owning the address.
    "net.ipv4.conf.all.arp_announce" = 2;
    "net.ipv4.conf.default.arp_announce" = 2;
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.default.arp_ignore" = 1;
  };
  powerManagement.cpuFreqGovernor = "performance";
}
