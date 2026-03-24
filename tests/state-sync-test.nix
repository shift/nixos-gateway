{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "state-sync-test";
{
  name = "state-sync-test";

  nodes.active =
    { config, pkgs, ... }:
    {
      imports = [ ../modules/state-sync.nix ];
      networking.hostName = "active";

      # Generate an SSH key for testing
      system.activationScripts.sshKey = ''
        mkdir -p /root/.ssh
        if [ ! -f /root/.ssh/id_rsa ]; then
          ${pkgs.openssh}/bin/ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
        fi
      '';

      services.gateway.stateSync = {
        enable = true;
        delay = 1; # Fast sync for test
        sshIdentityFile = "/root/.ssh/id_rsa";
        targets = [
          {
            source = "/var/lib/sync-test";
            destinationHost = "standby";
            destinationDir = "/var/lib/sync-test-dest";
          }
        ];
      };

      services.openssh.enable = true;
      services.openssh.settings.StrictModes = false; # Relax for test
    };

  nodes.standby =
    { config, pkgs, ... }:
    {
      networking.hostName = "standby";
      services.openssh.enable = true;
      services.openssh.settings.PermitRootLogin = "yes";
      services.openssh.settings.StrictModes = false; # Relax for test
    };

  testScript = ''
    start_all()

    # 1. Setup SSH Keys
    # Extract public key from active and add to standby authorized_keys
    pub_key = active.succeed("cat /root/.ssh/id_rsa.pub")
    standby.succeed("mkdir -p /root/.ssh")
    standby.succeed(f"echo '{pub_key}' >> /root/.ssh/authorized_keys")
    standby.succeed("chmod 600 /root/.ssh/authorized_keys")

    # 2. Setup Source and Dest directories
    active.succeed("mkdir -p /var/lib/sync-test")
    standby.succeed("mkdir -p /var/lib/sync-test-dest")

    # 3. Start Lsyncd
    active.systemctl("restart lsyncd")
    active.wait_for_unit("lsyncd.service")

    # 4. Create File on Active
    active.succeed("echo 'Hello Sync' > /var/lib/sync-test/file1.txt")

    # 5. Wait for Sync (lsyncd delay is 1s, + rsync overhead)
    # We poll standby
    standby.wait_until_succeeds("test -f /var/lib/sync-test-dest/file1.txt")
    standby.succeed("grep 'Hello Sync' /var/lib/sync-test-dest/file1.txt")

    # 6. Verify Modification Sync
    active.succeed("echo 'Updated Content' > /var/lib/sync-test/file1.txt")
    standby.wait_until_succeeds("grep 'Updated Content' /var/lib/sync-test-dest/file1.txt")
  '';
}
