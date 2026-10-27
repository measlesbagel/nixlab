# Pull deploys: each host polls main, builds nixosConfigurations.<hostname>
# and switches. Nothing outside the lab holds a credential that reaches it.
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # A switch this does not confirm is rolled back by modules/watchdog.nix.
  confirm = pkgs.writeShellApplication {
    name = "comin-confirm";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
    ];
    text = ''
      if [ "''${COMIN_STATUS:-}" != "done" ]; then
        echo "deploy of ''${COMIN_GIT_SHA:-?} ended ''${COMIN_STATUS:-?}: ''${COMIN_ERROR_MSG:-}"
        exit 0
      fi

      # Retried for 5 minutes so a slow network restart is not a rollback.
      # Reaching GitHub proves the host can still pull its next fix.
      for _ in $(seq 30); do
        if /run/current-system/sw/bin/deploy-health \
          && curl -sSf --max-time 10 -o /dev/null https://github.com; then
          exec /run/current-system/sw/bin/deploy-confirm
        fi
        sleep 10
      done

      echo "not confirming $COMIN_GIT_SHA; the watchdog rolls it back"
      exit 1
    '';
  };
in
{
  imports = [ inputs.comin.nixosModules.comin ];

  services.comin = {
    enable = true;
    # The module prefers pkgs.comin, which can lag the module's options.
    package = inputs.comin.packages.${pkgs.stdenv.hostPlatform.system}.comin;
    remotes = [
      {
        name = "origin";
        url = "https://github.com/measlesbagel/nixlab.git";
        branches.main.name = "main";
        # Branch protection covers only main; anyone who can push a branch
        # could otherwise deploy through testing-<host>.
        branches.testing.name = "";
      }
    ];
    # A Spark compiles its NVIDIA kernel when Attic lacks it.
    buildTimeout = 7200;
    postDeploymentCommand = lib.getExe confirm;
    # Only a tip commit GitHub made (web-UI merges, Dependabot) deploys, so a
    # push from outside GitHub, even with stolen credentials, cannot. Key
    # 968479A1AFF927E37D1A566BB5690EEEBB952194 from github.com/web-flow.gpg.
    gpgPublicKeyPaths = [ "${./github-web-flow.asc}" ];
  };
}
