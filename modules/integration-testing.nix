{ config, lib, ... }:

with lib;

let
  cfg = config.services.taskVerification.integration;
in

{
  options.services.taskVerification.integration = {
    enable = mkEnableOption "Integration testing framework";

    tests = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = "Integration tests to run";
    };

    modules = mkOption {
      type = types.listOf types.str;
      default = [ "dns" "dhcp" "network" "firewall" "routing" ];
      description = "Modules to test integration with";
    };

    dependencies = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = {
        dns = [ "network" ];
        dhcp = [ "network" "dns" ];
        firewall = [ "network" ];
        routing = [ "network" ];
      };
      description = "Module dependencies for integration testing";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.integration-test-runner = {
      description = "Integration Test Runner";
      wantedBy = [ "multi-user.target" ];
      after = [ "functional-test-runner.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./integration-test-runner.nix {
          inherit (cfg) tests modules dependencies;
        }}/bin/integration-test-runner";
        Restart = "on-failure";
        User = "verification";
        Group = "verification";
      };
    };
  };
}