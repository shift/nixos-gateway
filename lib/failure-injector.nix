{ pkgs, ... }:

let
  inherit (pkgs) lib;
in
{
  # Generates a script to inject a specific type of failure
  mkFailureScript =
    {
      type,
      target,
      duration ? "30s",
      ...
    }@args:
    if type == "service-crash" then
      ''
        echo "Injecting failure: Service Crash on ${target}"
        pid=$(systemctl show --property MainPID --value ${target})
        if [ -n "$pid" ] && [ "$pid" != "0" ]; then
          kill -9 "$pid"
          echo "Killed process $pid for service ${target}"
        else
          echo "Service ${target} not running or no PID found"
          exit 1
        fi
      ''
    else if type == "interface-down" then
      ''
        echo "Injecting failure: Interface Down on ${target}"
        ip link set ${target} down
        echo "Interface ${target} set to DOWN"

        # Schedule recovery if duration is set
        if [ -n "${duration}" ]; then
          nohup sh -c "sleep ${duration}; ip link set ${target} up; echo 'Interface ${target} restored'" >/dev/null 2>&1 &
        fi
      ''
    else if type == "packet-loss" then
      ''
        echo "Injecting failure: Packet Loss on ${target}"
        # Requires tc
        tc qdisc add dev ${target} root netem loss 20%
        echo "Added 20% packet loss to ${target}"

        if [ -n "${duration}" ]; then
           nohup sh -c "sleep ${duration}; tc qdisc del dev ${target} root netem; echo 'Packet loss removed from ${target}'" >/dev/null 2>&1 &
        fi
      ''
    else if type == "resource-exhaustion" then
      ''
        echo "Injecting failure: Resource Exhaustion (Memory)"
        # Run stress-ng for the specified duration
        timeout ${duration} ${pkgs.stress-ng}/bin/stress-ng --vm 1 --vm-bytes 80% --timeout ${duration}
      ''
    else
      ''
        echo "Unknown failure type: ${type}"
        exit 1
      '';
}
