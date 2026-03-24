{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "failure-scenario-test";

    # Setup aliases
    jq = "${pkgs.jq}/bin/jq"

    # Wait for system to settle
    machine.wait_for_unit("multi-user.target")

    # --- SCENARIO 1: Automated Service Recovery (Crash & Restart) ---
    print("--- SCENARIO 1: Automated Service Recovery (Crash & Restart) ---")
    machine.wait_for_unit("test-service.service")
    machine.wait_for_open_port(8000)

    # Get initial PID
    initial_pid = machine.succeed("systemctl show --property MainPID --value test-service").strip()
    print(f"Initial PID: {initial_pid}")

    # Inject Crash Failure
    machine.succeed(f"kill -9 {initial_pid}")

    # Wait for systemd to restart it
    machine.sleep(3)

    # Verify new PID
    new_pid = machine.succeed("systemctl show --property MainPID --value test-service").strip()
    print(f"New PID: {new_pid}")

    if initial_pid == new_pid:
        raise Exception("Service did not restart (PID matches)")

    machine.wait_for_open_port(8000)
    print("✅ Service successfully recovered from crash.")


    # --- SCENARIO 2: Manual Recovery / Permanent Failure Detection ---
    print("--- SCENARIO 2: Manual Recovery / Permanent Failure Detection ---")
    machine.wait_for_unit("fragile-service.service")
    machine.wait_for_open_port(8001)

    fragile_pid = machine.succeed("systemctl show --property MainPID --value fragile-service").strip()
    machine.succeed(f"kill -9 {fragile_pid}")
    machine.sleep(2)

    # Check if the service is in failed state
    status_check = machine.succeed("systemctl show --property ActiveState --value fragile-service").strip()
    print(f"Fragile service status: {status_check}")

    if status_check != "failed":
         raise Exception(f"Fragile service should be failed, but is {status_check}")
        
    print("✅ Fragile service correctly entered failed state.")


    # --- SCENARIO 3: Network Resilience (Interface Flapping) ---
    print("--- SCENARIO 3: Network Resilience (Interface Flapping) ---")

    # Create dummy interface
    machine.succeed("ip link add dummy0 type dummy")
    machine.succeed("ip link set dummy0 up")
    machine.succeed("ip addr add 192.168.100.1/24 dev dummy0")

    # Inject Failure: Bring interface down
    machine.succeed("ip link set dummy0 down")

    # Verify the state is DOWN
    operstate = machine.succeed(f"ip -j link show dummy0 | {jq} -r '.[0].operstate'").strip()
    print(f"Interface operstate: {operstate}")

    if operstate != "DOWN":
         # Sometimes dummy interfaces are weird. Let's try checking flags.
         flags = machine.succeed(f"ip -j link show dummy0 | {jq} -r '.[0].flags[]'").strip()
         if "UP" in flags:
             raise Exception(f"Interface should be DOWN but flags contain UP: {flags}")

    print("✅ Interface is confirmed DOWN.")

    # Recovery: Bring interface up
    machine.succeed("ip link set dummy0 up")
    machine.sleep(1)

    # Verify UP
    operstate_up = machine.succeed(f"ip -j link show dummy0 | {jq} -r '.[0].operstate'").strip()
    # Dummy interfaces usually show UNKNOWN when up, or UP
    print(f"Interface operstate after recovery: {operstate_up}")

    if operstate_up == "DOWN":
         raise Exception("Interface is still DOWN after recovery")
         
    print("✅ Network recovery verified.")


    # --- SCENARIO 4: Resource Exhaustion Resilience ---
    print("--- SCENARIO 4: Resource Exhaustion Resilience ---")

    machine.succeed("stress-ng --cpu 2 --timeout 5s &")
    machine.sleep(1)

    # Try to write a file and read it while CPU is stressed
    machine.succeed("echo 'survival check' > /tmp/survival.txt")
    content = machine.succeed("cat /tmp/survival.txt").strip()
    if content != "survival check":
        raise Exception("File I/O failed under load")
        
    print("✅ System remained responsive under synthetic load.")

    print("All failure scenarios passed.")
  '';

in
{
  name = "task-42-failure-scenarios";

  nodes.machine =
    { config, pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        stress-ng
        iproute2
        jq
        bc
      ];

      # Configure a dummy service to test crashing/restarting
      systemd.services.test-service = {
        description = "Test Service for Failure Scenarios";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8000";
          Restart = "always";
          RestartSec = "1s";
        };
      };

      # Configure a secondary dummy service that does NOT restart automatically
      systemd.services.fragile-service = {
        description = "Fragile Service that stays down";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8001";
          Restart = "no";
        };
      };
    };

  inherit testScript;
}
