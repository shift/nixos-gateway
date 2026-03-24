{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.interactive-simulator;
in

{
  options.services.interactive-simulator = {
    enable = mkEnableOption "Interactive VM Simulator for human verification";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for the web interface";
    };

    features = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of features to enable in the simulator";
    };

    networkConfig = mkOption {
      type = types.attrs;
      default = {};
      description = "Network configuration for the simulated environment";
    };

    template = mkOption {
      type = types.str;
      default = "basic";
      description = "Template to use for the simulator";
    };
  };

  config = mkIf cfg.enable {
    # VM orchestration service
    systemd.services.interactive-simulator = {
      description = "Interactive VM Simulator";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./simulator-orchestrator.nix {
          inherit (cfg) features networkConfig template;
        }}/bin/simulator-orchestrator";
        Restart = "always";
        User = "simulator";
        Group = "simulator";
      };
    };

    # Web API service
    systemd.services.simulator-api = {
      description = "Simulator Web API";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.nodejs}/bin/node ${pkgs.callPackage ./simulator-web-interface.nix {}}/share/simulator-web/server.js";
        WorkingDirectory = "${pkgs.callPackage ./simulator-web-interface.nix {}}/share/simulator-web";
        Restart = "always";
        User = "simulator";
        Group = "simulator";
      };
    };

    # Test runner service
    systemd.services.simulator-test-runner = {
      description = "Simulator Automated Test Runner";
      wantedBy = [ "multi-user.target" ];
      after = [ "simulator-api.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./test-runner.nix {
          scenarios = cfg.features;
          outputDir = "/var/lib/simulator/test-results";
        }}/bin/test-runner";
        Restart = "on-failure";
        User = "simulator";
        Group = "simulator";
      };
    };

    # Web interface service
    services.nginx = {
      enable = true;
      virtualHosts."simulator" = {
        listen = [{ addr = "0.0.0.0"; port = cfg.port; }];
        root = "${pkgs.callPackage ./simulator-web-interface.nix {}}/share/simulator-web";
        locations."/api/" = {
          proxyPass = "http://127.0.0.1:3000";
        };
      };
    };

    # Create simulator user
    users.users.simulator = {
      isSystemUser = true;
      group = "simulator";
      home = "/var/lib/simulator";
      createHome = true;
    };

    users.groups.simulator = {};

    # State directory
    systemd.tmpfiles.rules = [
      "d /var/lib/simulator 0750 simulator simulator -"
      "d /var/lib/simulator/vms 0750 simulator simulator -"
      "d /var/lib/simulator/logs 0750 simulator simulator -"
    ];
  };
}