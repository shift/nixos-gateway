{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.failureScenarios;
  injector = import ../lib/failure-injector.nix { inherit lib; };

  defaultScenarios = [
    {
      name = "dns-service-crash";
      description = "Simulate DNS service crash and recovery";
      category = "service";
      failure = {
        type = "service-crash";
        target = "systemd-resolved"; # Using resolved as a generic target for default
        method = "systemctl-stop";
      };
      recovery = {
        automatic = true;
        steps = {
          timeout = "10s";
        };
      };
    }
  ];

in
{
  options.services.gateway.failureScenarios = {
    enable = lib.mkEnableOption "Failure Scenario Testing Framework";

    scenarios = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = defaultScenarios;
      description = "List of failure scenarios to execute";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeScriptBin "gateway-chaos-test" (injector.mkFailureScript pkgs cfg.scenarios))

      # Tools for injection
      pkgs.iproute2
      pkgs.systemd
      pkgs.jq
    ];
  };
}
