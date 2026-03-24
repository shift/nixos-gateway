{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.hardwareTesting;
  hardwareValidator = import ../lib/hardware-validator.nix { inherit lib pkgs; };

  testScript = hardwareValidator.mkHardwareTestScript cfg;

  testRunnerBin = pkgs.writeScriptBin "gateway-hardware-test" testScript;

in
{
  options.services.gateway.hardwareTesting = {
    enable = mkEnableOption "Hardware Testing Framework";

    platforms = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "Platform definitions";
    };

    testSuites = mkOption {
      type = types.attrs;
      default = { };
      description = "Test suite definitions";
    };

    automation = mkOption {
      type = types.attrs;
      default = { };
      description = "Automation settings";
    };

    reporting = mkOption {
      type = types.attrs;
      default = { };
      description = "Reporting settings";
    };

    integration = mkOption {
      type = types.attrs;
      default = { };
      description = "Integration settings";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ testRunnerBin ];

    # Ensure results directory exists
    systemd.tmpfiles.rules = [
      "d /var/lib/gateway/hardware-tests 0755 root root -"
    ];
  };
}
