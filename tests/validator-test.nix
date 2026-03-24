{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "interactive-validator-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ ../modules/dev-tools/validator.nix ];

      # Inject some configuration to validate
      networking.hostName = "validator-test";
      networking.domain = "example.com";
      networking.interfaces.eth1.ipv4.addresses = [
        {
          address = "192.168.1.50";
          prefixLength = 24;
        }
      ];

      services.openssh.enable = true;
      services.openssh.settings.PermitRootLogin = "yes"; # Should trigger warning
    };

  testScript = ''
    start_all()

    # 1. Verify Tool Installation
    machine.succeed("which gateway-validator")

    # 2. Run Validation on System Config (via alias or direct path)
    # The alias 'validate-system' points to a store path JSON.
    # Note: alias expansion in machine.succeed might not work like interactive shell.
    # We will assume we can find the json dump or create one.

    # Let's create a test JSON file with known issues
    machine.succeed("echo '{\"networking\": {\"interfaces\": {\"eth0\": {\"ipv4\": {\"addresses\": [{\"address\": \"999.999.999.999\"}]}}}}}' > /tmp/bad_config.json")

    # 3. Test Failure Case
    machine.fail("gateway-validator --config /tmp/bad_config.json")

    # 4. Test Success Case (with warning)
    # We dump a minimal valid config
    machine.succeed("echo '{\"networking\": {\"interfaces\": {\"eth0\": {\"ipv4\": {\"addresses\": [{\"address\": \"10.0.0.1\"}]}}}}, \"services\": {\"openssh\": {\"enable\": true, \"permitRootLogin\": \"yes\"}}}' > /tmp/warn_config.json")

    output = machine.succeed("gateway-validator --config /tmp/warn_config.json")
    print(output)
    # Check for color codes in output or plain text
    assert "SSH: PermitRootLogin" in output
    assert "Interface eth0: IP 10.0.0.1 valid" in output
  '';
}
