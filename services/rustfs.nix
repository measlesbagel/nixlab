# restic target for every host. /tank/objects is snapshotted, so backups a host
# deletes (or has deleted for it) can still be rolled back.
{ pkgs, ... }:
let
  port = 9000;
  storage = "/tank/objects";
in
{
  services.rustfs = {
    enable = true;
    # rustfs 1.0.4's aws-lc-sys is built with AWS_LC_SYS_USE_SYSTEM=1 but
    # nixpkgs gives it no aws-lc, so the build fails. nixpkgs master adds
    # pkg-config, zstd and aws-lc (with rustfs 1.0.5); drop this once that lands.
    package = pkgs.rustfs.overrideAttrs (old: {
      nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.pkg-config ];
      buildInputs = (old.buildInputs or [ ]) ++ [
        pkgs.zstd
        pkgs.aws-lc
      ];
    });
    environmentFile = "/var/lib/opnix/secrets/rustfsResticEnv";
    settings = {
      RUSTFS_VOLUMES = storage;
      RUSTFS_ADDRESS = ":${toString port}";
      RUSTFS_CONSOLE_ENABLE = "false";
    };
  };
  systemd.services.rustfs.unitConfig.RequiresMountsFor = [ storage ];

  # The same 1Password item as the restic clients, a field holding:
  #   RUSTFS_ACCESS_KEY=<key>      RUSTFS_SECRET_KEY=<secret>
  #   AWS_ACCESS_KEY_ID=<key>      AWS_SECRET_ACCESS_KEY=<secret>
  # RustFS reads the first pair, restic the second; both hold the same values.
  services.onepassword-secrets.secrets.rustfsResticEnv = {
    reference = "op://homelab/rustfs-restic-env/env";
    services = [ "rustfs" ];
  };

  networking.firewall.allowedTCPPorts = [ port ];

  # Only restic uses RustFS, and it holds its connections for the whole run.
  homelab.reboot.busyWhen."a restic client upload" =
    "[ -n \"$(${pkgs.iproute2}/bin/ss -Htn state established '( sport = :${toString port} )')\" ]";
}
