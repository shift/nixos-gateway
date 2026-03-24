{
  # ===========================================================================
  # NixOS Network Fault Injection Library
  # ===========================================================================
  # This library injects a Python DSL into the NixOS Test Driver (testScript).
  # It abstracts complex QEMU, Traffic Control (tc), and iptables commands.
  #
  # USAGE:
  #   testScript = ''
  #     ${testUtils.pythonLib}
  #     start_all()
  #     link = PhysicalLink(router, "eth0", 1)
  #     link.unplug()
  #   '';
  # ===========================================================================

  pythonLib = ''
    import json
    import time
    import re

    # =============================================================================
    # CLASS: PhysicalLink
    # Purpose: Simulates Layer 1 (Physical) failures on the Device Under Test (DUT).
    # Use cases: Cable unplug, hardware interface failure.
    # =============================================================================
    class PhysicalLink:
        def __init__(self, machine, interface_name, qemu_index):
            """
            machine: The VM object (e.g., router)
            interface_name: The OS interface name (e.g., 'eth0', 'wan1')
            qemu_index: The index of the NIC in QEMU (1 for nic1/eth1, etc.)
            """
            self.machine = machine
            self.iface = interface_name
            self.qemu_id = f"nic{qemu_index}"

        def unplug(self):
            """Simulates physical cable disconnection (Carrier Loss)."""
            print(f">>> [Physical] Unplugging cable {self.iface} ({self.qemu_id})...")
            # Uses QEMU Monitor to set link status electrically off
            self.machine.send_monitor_command(f"set_link {self.qemu_id} off")

        def plug(self):
            """Simulates physical cable connection."""
            print(f">>> [Physical] Plugging cable {self.iface} back in...")
            self.machine.send_monitor_command(f"set_link {self.qemu_id} on")


    # =============================================================================
    # CLASS: UpstreamISP
    # Purpose: Simulates Layer 2-7 failures on the 'World' node.
    # Use cases: Physics simulation (Satellite/4G), Captive portals, Brownouts.
    # =============================================================================
    class UpstreamISP:
        def __init__(self, machine, interface_name):
            """
            machine: The World/ISP VM
            interface_name: The interface on the ISP node connected to the router
            """
            self.machine = machine
            self.iface = interface_name

        # --- Layer 1/2: Physics Simulation Profiles ---

        def simulate_connection_type(self, type_name):
            """
            Applies a pre-set physics profile to the link to simulate specific
            technologies like 4G, Satellite, Cable, or DSL.
            """
            print(f">>> [ISP] Applying connection profile: {type_name.upper()} on {self.iface}")
            
            # Reset existing shaping and MTU
            self.machine.execute(f"tc qdisc del dev {self.iface} root")
            self.machine.execute(f"ip link set dev {self.iface} mtu 1500")

            if type_name == "fiber":
                # Standard FTTH: <5ms, Jitter <1ms, 1Gbit
                self.machine.succeed(
                    f"tc qdisc add dev {self.iface} root netem delay 2ms 1ms rate 1gbit"
                )

            elif type_name == "dsl":
                # VDSL2/PPPoE: 1492 MTU, Asymmetric, moderate latency
                self.machine.succeed(f"ip link set dev {self.iface} mtu 1492")
                self.machine.succeed(
                    f"tc qdisc add dev {self.iface} root netem delay 15ms 5ms rate 50mbit"
                )

            elif type_name == "cable":
                # DOCSIS 3.0/3.1: Asymmetric, moderate latency, variable jitter
                self.machine.succeed(f"ip link set dev {self.iface} mtu 1500")
                self.machine.succeed(
                    f"tc qdisc add dev {self.iface} root netem delay 20ms 10ms distribution normal rate 300mbit"
                )

            elif type_name == "cable_powerboost":
                # DOCSIS "SpeedBoost": Burst to 100Mbit for ~10s, then throttle to 20Mbit.
                # Critical for testing Bufferbloat/SQM.
                # 1. Base Latency
                self.machine.succeed(
                    f"tc qdisc add dev {self.iface} root handle 1: netem delay 20ms 5ms distribution normal"
                )
                # 2. Token Bucket Filter (TBF) for Burst logic
                # burst 80mb approx = 100mbit * 6-8 seconds
                self.machine.succeed(
                    f"tc qdisc add dev {self.iface} parent 1: handle 10: tbf rate 20mbit burst 80mb peakrate 100mbit limit 100mb"
                )

            elif type_name == "4g":
                # LTE: High jitter, bursts, packet loss
                self.machine.succeed(
                    f"tc qdisc add dev {self.iface} root netem delay 50ms 20ms distribution pareto loss 0.1% rate 20mbit"
                )

            elif type_name == "3g":
                # Legacy Cellular
                self.machine.succeed(
                    f"tc qdisc add dev {self.iface} root netem delay 150ms 50ms rate 2mbit"
                )

            elif type_name == "satellite_geo":
                # Viasat/HughesNet: Massive Latency
                self.machine.succeed(
                    f"tc qdisc add dev {self.iface} root netem delay 600ms 50ms loss 1% rate 25mbit"
                )

            elif type_name == "satellite_leo":
                # Starlink: Variable latency
                self.machine.succeed(
                    f"tc qdisc add dev {self.iface} root netem delay 40ms 15ms rate 150mbit"
                )

            elif type_name == "wifi_public":
                # Coffee Shop: High loss, very high jitter
                self.machine.succeed(
                    f"tc qdisc add dev {self.iface} root netem delay 10ms 50ms loss 5% rate 10mbit"
                )
            
            else:
                raise Exception(f"Unknown connection profile: {type_name}")

        def simulate_obstruction(self, duration=3):
            """Simulates 100% packet loss (e.g., Starlink obstruction) while link stays UP."""
            print(f">>> [ISP] Simulating Connection Obstruction ({duration}s)...")
            self.machine.succeed(f"tc filter add dev {self.iface} protocol ip parent 1:0 prio 1 u32 match ip dst 0.0.0.0/0 flowid 1:1 action drop")
            time.sleep(duration)
            self.machine.succeed(f"tc filter del dev {self.iface} protocol ip parent 1:0 prio 1")
            print(">>> [ISP] Obstruction cleared.")

        # --- Layer 2: Manual Shaping ---

        def set_link_properties(self, latency="0ms", jitter="0ms", loss="0%", rate="1000mbit"):
            """Manually sets latency, packet loss, and bandwidth limits."""
            print(f">>> [ISP] Degrading link {self.iface}: {latency} delay, {loss} loss, {rate} cap")
            self.machine.execute(f"tc qdisc del dev {self.iface} root")
            self.machine.succeed(
                f"tc qdisc add dev {self.iface} root netem delay {latency} {jitter} loss {loss} rate {rate}"
            )

        def corrupt_packets(self, percent="5%"):
            """Randomly corrupts packet bits (Tests TCP Checksum Offloading)."""
            print(f">>> [ISP] Corrupting {percent} of packets on {self.iface}")
            self.machine.execute(f"tc qdisc del dev {self.iface} root")
            self.machine.succeed(f"tc qdisc add dev {self.iface} root netem corrupt {percent}")

        def clear_shaping(self):
            print(f">>> [ISP] Restoring signal quality on {self.iface}")
            self.machine.execute(f"tc qdisc del dev {self.iface} root")

        # --- Layer 3/4/7: Logical Failures ---

        def start_captive_portal(self, portal_port=8080):
            """Redirects HTTP (TCP/80) to local port (Walled Garden simulation)."""
            print(f">>> [ISP] Activating CAPTIVE PORTAL on {self.iface}")
            self.machine.succeed(
                f"iptables -t nat -A PREROUTING -i {self.iface} -p tcp --dport 80 -j REDIRECT --to-port {portal_port}"
            )

        def stop_captive_portal(self, portal_port=8080):
            print(f">>> [ISP] Deactivating Captive Portal on {self.iface}")
            self.machine.succeed(
                f"iptables -t nat -D PREROUTING -i {self.iface} -p tcp --dport 80 -j REDIRECT --to-port {portal_port}"
            )

        def simulate_blackhole(self):
            """Link is UP, but packets are dropped (Dead Peer Detection test)."""
            print(f">>> [ISP] Blackholing traffic on {self.iface}")
            self.machine.succeed(f"iptables -I INPUT -i {self.iface} -j DROP")

        def clear_blackhole(self):
            print(f">>> [ISP] Clearing Blackhole on {self.iface}")
            self.machine.succeed(f"iptables -D INPUT -i {self.iface} -j DROP")

        def block_dhcp(self):
            """Stops answering DHCP requests."""
            print(f">>> [ISP] Blocking DHCP on {self.iface}")
            self.machine.succeed(f"iptables -I INPUT -i {self.iface} -p udp --dport 67 -j DROP")

        def restore_dhcp(self):
            print(f">>> [ISP] Restoring DHCP on {self.iface}")
            self.machine.succeed(f"iptables -D INPUT -i {self.iface} -p udp --dport 67 -j DROP")

        def poison_dns(self, target_domain, fake_ip):
            """Spoofs DNS responses via /etc/hosts."""
            print(f">>> [ISP] Poisoning DNS: {target_domain} -> {fake_ip}")
            self.machine.succeed(f"echo '{fake_ip} {target_domain}' >> /etc/hosts")

        def clear_dns_poisoning(self):
            print(">>> [ISP] Clearing DNS poisoning")
            self.machine.succeed("sed -i '/^# POISON/d' /etc/hosts")


    # =============================================================================
    # CLASS: TrafficGen
    # Purpose: Generates and measures traffic for Bandwidth/QoS verification.
    # Requirements: 'iperf3' on client and server.
    # =============================================================================
    class TrafficGen:
        def __init__(self, client_vm, server_vm):
            self.client = client_vm
            self.server = server_vm

        def start_server(self, port=5201):
            self.server.execute("pkill iperf3")
            self.server.succeed(f"iperf3 -s -p {port} -D")

        def measure_bandwidth(self, target_ip, time_sec=5, port=5201, expected_mbps=None, tolerance=0.2):
            """Runs iperf3 client, returns float (Mbps). Asserts if expected_mbps set."""
            print(f">>> [Traffic] Measuring bandwidth to {target_ip}...")
            cmd = f"iperf3 -c {target_ip} -p {port} -t {time_sec} -J"
            status, output = self.client.execute(cmd)
            
            if status != 0:
                print(f"Iperf failed: {output}")
                raise Exception("Iperf3 execution failed")

            try:
                data = json.loads(output)
                bps = data['end']['sum_received']['bits_per_second']
                mbps = bps / 1_000_000.0
                print(f">>> [Traffic] Result: {mbps:.2f} Mbps")
                
                if expected_mbps:
                    lower = expected_mbps * (1.0 - tolerance)
                    upper = expected_mbps * (1.0 + tolerance)
                    if not (lower <= mbps <= upper):
                        raise Exception(
                            f"Bandwidth violation! Expected {expected_mbps} Mbps (+/- {tolerance*100}%), "
                            f"got {mbps:.2f} Mbps"
                        )
                return mbps
            except KeyError as e:
                raise Exception(f"Failed to parse iperf output: {e}")


    # =============================================================================
    # CLASS: RoutingPeer
    # Purpose: Manipulates routing tables to simulate BGP/OSPF updates.
    # =============================================================================
    class RoutingPeer:
        def __init__(self, node):
            self.node = node

        def announce_route(self, prefix, next_hop):
            """Injects a route (BGP Advertisement)."""
            print(f">>> [Routing] Announcing prefix {prefix} via {next_hop}")
            self.node.succeed(f"ip route add {prefix} via {next_hop}")

        def withdraw_route(self, prefix):
            """Removes a route (BGP Withdrawal)."""
            print(f">>> [Routing] Withdrawing prefix {prefix}")
            self.node.execute(f"ip route del {prefix}")


    # =============================================================================
    # CLASS: SecurityAuditor
    # Purpose: Verification of Firewall rules, Port Security, and Access Control.
    # Requirements: 'nc' (netcat) on attacker.
    # =============================================================================
    class SecurityAuditor:
        def __init__(self, attacker_vm):
            self.attacker = attacker_vm

        def assert_port_open(self, target_ip, port, proto="tcp"):
            print(f">>> [Sec] Verifying {target_ip}:{port} ({proto}) is OPEN...")
            flag = "-u" if proto == "udp" else ""
            self.attacker.succeed(f"nc -z {flag} -w 2 {target_ip} {port}")

        def assert_port_blocked(self, target_ip, port, proto="tcp"):
            print(f">>> [Sec] Verifying {target_ip}:{port} ({proto}) is BLOCKED...")
            flag = "-u" if proto == "udp" else ""
            self.attacker.fail(f"nc -z {flag} -w 2 {target_ip} {port}")


    # =============================================================================
    # CLASS: LogInspector
    # Purpose: Verifies system logs for expected patterns.
    # =============================================================================
    class LogInspector:
        def __init__(self, machine):
            self.machine = machine

        def assert_journal_contains(self, unit, pattern, since="10m ago"):
            print(f">>> [Logs] Searching {unit} for '{pattern}'...")
            cmd = f"journalctl -u {unit} --since '{since}' --no-pager | grep '{pattern}'"
            status, output = self.machine.execute(cmd)
            if status != 0:
                _, recent = self.machine.execute(f"journalctl -u {unit} -n 10 --no-pager")
                raise Exception(f"Log pattern '{pattern}' not found in {unit}.\nRecent logs:\n{recent}")

        def wait_for_log(self, unit, pattern, timeout=30):
            print(f">>> [Logs] Waiting for '{pattern}' in {unit}...")
            start = time.time()
            while time.time() - start < timeout:
                status, _ = self.machine.execute(f"journalctl -u {unit} --since '1m ago' --no-pager | grep '{pattern}'")
                if status == 0: return
                time.sleep(1)
            raise Exception(f"Timed out waiting for log '{pattern}' in {unit}")


    # =============================================================================
    # CLASS: VPNProbe
    # Purpose: Deep inspection of WireGuard/Tailscale tunnels.
    # =============================================================================
    class VPNProbe:
        def __init__(self, machine, tool="wg"):
            self.machine = machine
            self.tool = tool

        def assert_handshake(self, interface, peer_pubkey_substr):
            print(f">>> [VPN] Verifying handshake on {interface} for peer *{peer_pubkey_substr}*...")
            cmd = f"wg show {interface} latest-handshakes"
            _, output = self.machine.execute(cmd)
            
            for line in output.splitlines():
                if peer_pubkey_substr in line:
                    parts = line.split()
                    if len(parts) > 1 and int(parts[1]) > 0:
                        return
                    else:
                        raise Exception(f"VPN Peer {peer_pubkey_substr} found, but NO handshake.")
            raise Exception(f"VPN Peer {peer_pubkey_substr} not found.")


    # =============================================================================
    # CLASS: StateMonitor
    # Purpose: Verifies consistency between nodes (HA) or against baseline (Drift).
    # =============================================================================
    class StateMonitor:
        def get_file_hash(self, machine, filepath):
            return machine.succeed(f"sha256sum {filepath}").split()[0]

        def assert_files_match(self, machine_a, machine_b, filepath):
            print(f">>> [State] Comparing {filepath} on {machine_a.name} vs {machine_b.name}...")
            hash_a = self.get_file_hash(machine_a, filepath)
            hash_b = self.get_file_hash(machine_b, filepath)
            if hash_a != hash_b:
                raise Exception(f"State Mismatch! {filepath} differs.")

        def assert_conntrack_sync(self, machine_a, machine_b, expected_src_ip):
            print(f">>> [State] Checking Conntrack Sync for src={expected_src_ip}...")
            cmd = f"conntrack -L | grep 'src={expected_src_ip}'"
            if machine_a.execute(cmd)[0] == 0 and machine_b.execute(cmd)[0] == 0:
                return True
            raise Exception("Conntrack Sync Failed.")


    # =============================================================================
    # CLASS: MetricTracker
    # Purpose: Collects performance data for SLO verification.
    # =============================================================================
    class MetricTracker:
        def __init__(self, machine):
            self.machine = machine
            self.latencies = []

        def ping_sample(self, target, count=10):
            print(f">>> [Metrics] Sampling latency to {target} (n={count})...")
            cmd = f"LC_ALL=C ping -c {count} -i 0.2 {target}"
            _, output = self.machine.execute(cmd)
            found = re.findall(r"time=([0-9.]+)", output)
            self.latencies.extend([float(x) for x in found])

        def assert_p95(self, threshold_ms):
            if not self.latencies: raise Exception("No metrics collected yet!")
            sorted_data = sorted(self.latencies)
            p95 = sorted_data[int(len(sorted_data) * 0.95)]
            print(f">>> [Metrics] p95 Latency: {p95}ms (Threshold: {threshold_ms}ms)")
            if p95 > threshold_ms:
                raise Exception(f"SLO Violation! p95 {p95}ms > {threshold_ms}ms")


    # =============================================================================
    # CLASS: SecretAuditor
    # Purpose: Safe verification of secret rotation without leaking data.
    # =============================================================================
    class SecretAuditor:
        def __init__(self, machine):
            self.machine = machine

        def assert_rotated(self, filepath, old_hash, old_mtime):
            print(f">>> [Secrets] Verifying rotation of {filepath}...")
            new_hash = self.machine.succeed(f"sha256sum {filepath}").split()[0]
            new_mtime = int(self.machine.succeed(f"stat -c %Y {filepath}").strip())

            if new_hash == old_hash: raise Exception("Secret Rotation Failed: Hash unchanged")
            if new_mtime <= old_mtime: raise Exception("Secret Rotation Failed: Timestamp old")
            return new_hash


    # =============================================================================
    # CLASS: DisasterSim
    # Purpose: Destructive testing for backups and recovery.
    # =============================================================================
    class DisasterSim:
        def __init__(self, machine):
            self.machine = machine

        def corrupt_file(self, filepath):
            print(f">>> [Disaster] Corrupting data in {filepath}...")
            self.machine.succeed(f"dd if=/dev/urandom of={filepath} bs=1024 count=1 conv=notrunc")

        def delete_file(self, filepath):
            print(f">>> [Disaster] Deleting {filepath}...")
            self.machine.succeed(f"rm -f {filepath}")

        def assert_restored(self, filepath, expected_hash, timeout=60):
            print(f">>> [Recovery] Waiting for restoration of {filepath}...")
            start = time.time()
            while time.time() - start < timeout:
                if self.machine.execute(f"[ -f {filepath} ]")[0] == 0:
                    curr = self.machine.succeed(f"sha256sum {filepath}").split()[0]
                    if curr == expected_hash: return
                time.sleep(2)
            raise Exception(f"Recovery Failed: {filepath} not restored.")


    # =============================================================================
    # CLASS: ContainerProbe
    # Purpose: Verifies connectivity from INSIDE containers (CNI testing).
    # =============================================================================
    class ContainerProbe:
        def __init__(self, machine, runtime="podman"):
            self.machine = machine
            self.runtime = runtime

        def assert_can_reach(self, container_name, target_ip, port=80):
            print(f">>> [Container] Verifying {container_name} -> {target_ip}:{port} (Allowed)...")
            cmd = f"{self.runtime} exec {container_name} nc -z -w 2 {target_ip} {port}"
            if self.machine.execute(cmd)[0] != 0:
                raise Exception(f"Policy Violation: {container_name} SHOULD reach {target_ip}, but failed.")

        def assert_blocked(self, container_name, target_ip, port=80):
            print(f">>> [Container] Verifying {container_name} -> {target_ip}:{port} (Blocked)...")
            cmd = f"{self.runtime} exec {container_name} nc -z -w 2 {target_ip} {port}"
            if self.machine.execute(cmd)[0] == 0:
                raise Exception(f"Policy Violation: {container_name} reached {target_ip}, but SHOULD BE BLOCKED.")


    # =============================================================================
    # CLASS: HardwareWatchdog
    # Purpose: Tests stability against rapid changes (Flapping) and Exhaustion.
    # =============================================================================
    class HardwareWatchdog:
        def __init__(self, machine):
            self.machine = machine

        def simulate_link_flap(self, interface_idx, count=10, interval=0.5):
            print(f">>> [Stress] Flapping link nic{interface_idx} {count} times...")
            for i in range(count):
                self.machine.send_monitor_command(f"set_link nic{interface_idx} off")
                time.sleep(interval)
                self.machine.send_monitor_command(f"set_link nic{interface_idx} on")
                time.sleep(interval)

        def assert_memory_stable(self, trigger_func, iterations=100, tolerance_mb=10):
            print(f">>> [Stress] Checking memory leak over {iterations} iterations...")
            self.machine.succeed("sync; echo 3 > /proc/sys/vm/drop_caches") 
            start_mem = int(self.machine.succeed("free -m | grep Mem | awk '{print $3}'").strip())
            
            for i in range(iterations):
                trigger_func()
            
            self.machine.succeed("sync; echo 3 > /proc/sys/vm/drop_caches")
            end_mem = int(self.machine.succeed("free -m | grep Mem | awk '{print $3}'").strip())
            
            diff = end_mem - start_mem
            print(f"\n>>> [Stress] Memory Change: {diff}MB")
            if diff > tolerance_mb:
                raise Exception(f"Memory Leak Detected! Grew by {diff}MB.")


    # =============================================================================
    # CLASS: ProtocolTester
    # Purpose: Tests MTU, Fragmentation, and specific protocol edge cases.
    # =============================================================================
    class ProtocolTester:
        def __init__(self, client_vm):
            self.client = client_vm

        def assert_mtu_path(self, target, size=1450, allow_frag=False):
            print(f">>> [Proto] Testing MTU {size} to {target} (DF={not allow_frag})...")
            payload = size - 28 
            frag_flag = "-M do" if not allow_frag else "-M dont"
            cmd = f"ping -c 1 {frag_flag} -s {payload} {target}"
            status, output = self.client.execute(cmd)
            
            if status != 0:
                if "Message too long" in output:
                    raise Exception(f"MTU Fail: Packet size {size} too big for local interface.")
                else:
                    raise Exception(f"Path MTU Blackhole: Packet size {size} dropped on path to {target}.")

        def flood_connections(self, target_ip, port=80, count=1000):
            print(f">>> [Proto] Flooding {target_ip} with {count} SYN packets...")
            self.client.succeed(f"timeout 10s hping3 -S -p {port} -c {count} -i u1000 {target_ip} 2>&1 || true")


    # =============================================================================
    # HELPER FUNCTIONS
    # =============================================================================
    def assert_connected(client, target="1.1.1.1", timeout=10):
        start = time.time()
        while time.time() - start < timeout:
            if client.execute(f"ping -c 1 -W 1 {target}")[0] == 0: return True
            time.sleep(1)
        raise Exception(f"Connectivity check to {target} failed after {timeout}s")

    print(">>> Test Utils Library Loaded <<<")
  '';
}
