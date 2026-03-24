{ pkgs, lib, ... }:

let
  # Import the modules we need to test
  qosModule = ../modules/qos.nix;
  appAwareQosModule = ../modules/app-aware-qos.nix;

  # Minimal mock configuration to satisfy module arguments
  eval = lib.evalModules {
    modules = [
      appAwareQosModule
      qosModule
      (
        { config, ... }:
        {
          # Mocking systemd/networking options usually provided by NixOS
          options = {
            # Required for services.gateway.interfaces to be defined from network module
            services.gateway.interfaces = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  wan = lib.mkOption { type = lib.types.str; };
                  lan = lib.mkOption { type = lib.types.str; };
                };
              };
            };
            services.gateway.redInterfaces = lib.mkOption { type = lib.types.listOf lib.types.str; };
            services.irqbalance = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            services.resolved = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            systemd.network = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };

            systemd.services = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            networking.nftables = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            boot.kernelModules = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            boot.kernel.sysctl = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            # Network module deps
            networking.enableIPv6 = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            networking.hostName = lib.mkOption {
              type = lib.types.str;
              default = "gw";
            };
            networking.networkmanager = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            networking.useNetworkd = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            networking.useDHCP = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
            networking.interfaces = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            networking.defaultGateway = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
            networking.nameservers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            networking.firewall = lib.mkOption {
              type = lib.types.attrs;
              default = {
                allowedTCPPorts = [ ];
                allowedUDPPorts = [ ];
              };
            };
            networking.nat = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            networking.vlans = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
          };
          config = {
            # Mocking system configuration
            services.gateway.interfaces = {
              wan = "eth0";
              lan = "eth1";
            };
            services.gateway.redInterfaces = [ "eth0" ];

            systemd.services = { };
            networking.nftables = {
              enable = true;
              tables = { };
            };

            # Test Configuration
            services.gateway.appAwareQoS = {
              enable = true;
              applications = {
                "streaming-video" = {
                  signatures = [
                    "netflix"
                    "youtube"
                  ];
                  shaping = {
                    priority = 2;
                    maxBandwidth = "50Mbit";
                    guaranteedBandwidth = "10Mbit";
                  };
                };
                "work-calls" = {
                  signatures = [ "zoom" ];
                  shaping = {
                    priority = 1;
                    maxBandwidth = "20Mbit";
                    guaranteedBandwidth = "5Mbit";
                  };
                };
              };
            };
          };
        }
      )
    ];
  };

  tcClasses = eval.config.services.gateway.qos.trafficClasses;
  nftablesContent = eval.config.networking.nftables.tables."qos-mangle".content;

in
pkgs.writeText "test-results" ''
  TEST RESULTS
  ============

  1. Traffic Classes Generation:
     - Expected 'streaming-video' and 'work-calls' to be present.
     ${
       if (lib.hasAttr "streaming-video" tcClasses && lib.hasAttr "work-calls" tcClasses) then
         "PASS: Classes found."
       else
         "FAIL: Classes missing."
     }
     
     - 'streaming-video' Priority: ${toString tcClasses."streaming-video".priority} (Expected: 2)
     ${if tcClasses."streaming-video".priority == 2 then "PASS" else "FAIL"}
     
     - 'work-calls' Priority: ${toString tcClasses."work-calls".priority} (Expected: 1)
     ${if tcClasses."work-calls".priority == 1 then "PASS" else "FAIL"}

  2. Nftables Rules Generation:
     - Checking for Netflix signature rules (tcp/80, tcp/443)...
     ${
       if (lib.hasInfix "meta l4proto tcp th dport 443" nftablesContent) then
         "PASS: Netflix HTTPS rule found."
       else
         "FAIL: Netflix HTTPS rule missing."
     }
       
     - Checking for Zoom signature rules (UDP/8801)...
     ${
       if (lib.hasInfix "meta l4proto udp th dport 8801" nftablesContent) then
         "PASS: Zoom UDP rule found."
       else
         "FAIL: Zoom UDP rule missing."
     }

     - Checking for Mark setting (should correspond to class IDs)
       streaming-video ID: ${toString tcClasses."streaming-video".id}
       work-calls ID: ${toString tcClasses."work-calls".id}
       
       Rules snippet (Full content for debugging):
       ---------------------------------------------------
       ${nftablesContent}
       ---------------------------------------------------
''
