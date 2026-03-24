{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "troubleshooting-trees-test";
{
  name = "troubleshooting-trees-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ ../modules/troubleshooting-trees.nix ];

      services.gateway.troubleshootingTrees = {
        enable = true;
        problems = [
          {
            id = "test-problem";
            title = "Test Connectivity";
            description = "Test problem for verification";
            category = "network";
            severity = "medium";
            decisionTree = {
              start = "check-ping";
              nodes = [
                {
                  id = "check-ping";
                  question = "Can you ping 8.8.8.8?";
                  yes = {
                    action = "success";
                    solution = "Network is fine";
                  };
                  no = "check-interface";
                }
                {
                  id = "check-interface";
                  question = "Is interface eth0 up?";
                  yes = {
                    action = "check-route";
                    solution = "Check routing table";
                  };
                  no = {
                    action = "bring-up";
                    solution = "ip link set eth0 up";
                    automated = true;
                  };
                }
              ];
            };
          }
        ];
      };
    };

  testScript = ''
    start_all()

    # 1. Verify Config File Generation
    machine.wait_for_file("/etc/gateway/troubleshooting/config.json")
    machine.succeed("cat /etc/gateway/troubleshooting/config.json | ${pkgs.jq}/bin/jq . > /dev/null")

    # 2. Verify Tool Availability
    machine.succeed("which gateway-diagnostic-engine")

    # 3. Test Listing Problems
    output_list = machine.succeed("gateway-diagnostic-engine list")
    print(output_list)
    assert "Test Connectivity" in output_list
    assert "test-problem" in output_list

    # 4. Test Diagnosis Execution
    # Our simple engine defaults to 'no' for answers in this mock version
    output_diagnose = machine.succeed("gateway-diagnostic-engine diagnose --problem test-problem")
    print(output_diagnose)
    assert "Starting Diagnosis: Test Connectivity" in output_diagnose
    assert "Q: Can you ping 8.8.8.8?" in output_diagnose
    # Since we default to 'no', it should go to check-interface
    assert "Q: Is interface eth0 up?" in output_diagnose
    # And 'no' again -> bring-up solution
    assert "Solution: ip link set eth0 up" in output_diagnose
  '';
}
