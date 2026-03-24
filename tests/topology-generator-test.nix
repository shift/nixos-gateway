{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "topology-generator-test";
{
  name = "topology-generator-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ ../modules/dev-tools/topology-generator.nix ];

      services.gateway.topologyGenerator.enable = true;

      # Inject some configuration to visualize
      networking.hostName = "viz-gateway";
      networking.domain = "test.lab";
      networking.interfaces.eth1.ipv4.addresses = [
        {
          address = "10.0.0.1";
          prefixLength = 24;
        }
      ];
      networking.interfaces.eth2.ipv4.addresses = [
        {
          address = "192.168.1.1";
          prefixLength = 24;
        }
      ];

      services.openssh.enable = true;
    };

  testScript = ''
    start_all()

    # 1. Verify Tool Installation
    machine.succeed("which gateway-topology")

    # 2. Create a dummy config file
    machine.succeed("echo '{\"networking\": {\"hostName\": \"viz-gateway\", \"interfaces\": {\"eth0\": {\"ipv4\": {\"addresses\": [{\"address\": \"10.0.0.1\"}]}}}}}' > /tmp/config.json")

    # 3. Generate Topology
    machine.succeed("gateway-topology --config /tmp/config.json --output /tmp/topology --format svg")

    # 4. Verify Output Exists
    machine.succeed("ls -l /tmp/topology.svg")

    # 5. Check Content (basic check)
    output = machine.succeed("cat /tmp/topology.svg")
    # SVG content might not contain the raw strings exactly as expected depending on Graphviz formatting
    # But it should contain the nodes
    print(output)
    # The config we injected in step 2 uses 'viz-gateway' as hostname.
    # Graphviz/SVG may encode hyphens as '&#45;' or similar
    assert "viz-gateway" in output or "viz&#45;gateway" in output
    # The config we injected in step 2 uses '10.0.0.1'
    assert "10.0.0.1" in output
  '';
}
