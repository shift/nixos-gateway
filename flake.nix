{
  description = "NixOS Gateway Configuration Framework";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.url = "github:nix-community/impermanence";
    engram.url = "github:vincents-ai/engram";
    engram.inputs.nixpkgs.follows = "nixpkgs";
    aethalloc.url = "github:shift/aethalloc";
    aethalloc.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-stable,
      disko,
      impermanence,
      engram,
      aethalloc,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "i686-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      nixosModules = {
        default =
          { config, lib, ... }:
          {
            imports = [ (import ./modules) aethalloc.nixosModules.default ];
            # Wire up the gateway-level aethalloc option to the upstream module.
            # This lives here (not in modules/aethalloc.nix) so that
            # services.aethalloc.* only exists when aethalloc.nixosModules.default
            # is actually imported — avoiding unknown-option errors in tests.
            config = lib.mkIf config.services.gateway.aethalloc.enable {
              services.aethalloc = {
                enable = true;
                services = config.services.gateway.aethalloc.services;
              };
            };
          };
        gateway =
          { config, lib, ... }:
          {
            imports = [ (import ./modules) aethalloc.nixosModules.default ];
            config = lib.mkIf config.services.gateway.aethalloc.enable {
              services.aethalloc = {
                enable = true;
                services = config.services.gateway.aethalloc.services;
              };
            };
          };
        dns = import ./modules/dns.nix;
        dhcp = import ./modules/dhcp.nix;
        disko = disko.nixosModules.disko;
        impermanence-module = impermanence.nixosModules.impermanence;
        monitoring = import ./modules/monitoring.nix;
        # security = import ./modules/security.nix;
        management-ui = import ./modules/management-ui.nix;
        troubleshooting = import ./modules/troubleshooting.nix;
        malware-detection = import ./modules/malware-detection.nix;
        backup-recovery = import ./modules/backup-recovery.nix;
        disaster-recovery = import ./modules/disaster-recovery.nix;
        config-drift = import ./modules/config-drift.nix;
        # network = import ./modules/network.nix;
        frr = import ./modules/frr.nix;
        policy-routing = import ./modules/policy-routing.nix;
        aethalloc = import ./modules/aethalloc.nix;
        # direct-connect = import ./modules/direct-connect.nix;  # Temporarily disabled
        # dev-tools-monitor = import ./modules/dev-tools/monitor.nix;  # Temporarily disabled
        # api-gateway = import ./modules/api-gateway.nix;  # Temporarily disabled - complex dependencies
        # nat-gateway = import ./modules/nat-gateway.nix;  # Temporarily disabled - complex dependencies
        # cdn = import ./modules/cdn.nix;  # Temporarily disabled
        # transit-gateway = import ./modules/transit-gateway.nix;  # Temporarily disabled
      };

      lib = {
        mkGatewayData = import ./lib/mk-gateway-data.nix;

        defaultFirewall = import ./lib/data-defaults.nix {
          type = "firewall";
        };

        defaultIDS = import ./lib/data-defaults.nix {
          type = "ids";
        };

        validators = import ./lib/validators.nix { inherit (nixpkgs) lib; };
        healthChecks = import ./lib/health-checks.nix { inherit (nixpkgs) lib; };
        configReload = import ./lib/config-reload.nix { inherit (nixpkgs) lib pkgs; };
        templateEngine = import ./lib/template-engine.nix { inherit (nixpkgs) lib; };
        environment = import ./lib/environment.nix { inherit (nixpkgs) lib; };
        secrets = import ./lib/secrets.nix { inherit (nixpkgs) lib; };
        secretRotation = import ./lib/secret-rotation.nix { inherit (nixpkgs) lib; };
        bgpConfig = import ./lib/bgp-config.nix { inherit (nixpkgs) lib; };
        natConfig = import ./lib/nat-config.nix { inherit (nixpkgs) lib pkgs; };
        natMonitoring = import ./lib/nat-monitoring.nix { inherit (nixpkgs) lib pkgs; };
        igwConfig = import ./lib/igw-config.nix { inherit (nixpkgs) lib; };
        apiGatewayConfig = import ./lib/api-gateway-config.nix { inherit (nixpkgs) lib; };
        apiGatewayPlugins = import ./lib/api-gateway-plugins.nix { inherit (nixpkgs) lib; };
        serviceMeshConfig = import ./lib/service-mesh-config.nix { inherit (nixpkgs) lib; };
        serviceMeshPolicies = import ./lib/service-mesh-policies.nix { inherit (nixpkgs) lib; };
        securityGroups = import ./lib/security-groups.nix { inherit (nixpkgs) lib; };
        policyRouting = import ./lib/policy-routing.nix { inherit (nixpkgs) lib; };
        troubleshootingEngine = import ./lib/troubleshooting-engine.nix { inherit (nixpkgs) lib; };
      };

      # ALIX NixOS configurations (i686, deployment-only, no local builds)
      # Uses nixpkgs-stable (24.11) for better i686 binary cache coverage
      # nixpkgs-unstable has broken i686 GHC/perl/nix build chain
      nixosConfigurations = {
        alix-networkd = nixpkgs-stable.lib.nixosSystem {
          system = "i686-linux";
          modules = [
            self.nixosModules.default
            ./hosts/alix.nix
            {
              # Overlay our custom packages so modules can reference pkgs.gateway-health etc.
              nixpkgs.overlays = [
                (final: prev: {
                  gateway-health = self.packages."${prev.stdenv.hostPlatform.system}".gateway-health;
                  gateway-setup = self.packages."${prev.stdenv.hostPlatform.system}".gateway-setup;
                })
              ];
              services.gateway.profile = "alix-networkd";
              services.gateway.enable = true;
              services.gateway.network.enable = true;
              services.gateway.interfaces = {
                lan = "eth1";
                wan = "eth0";
              };

              # Minimal data so modules can evaluate
              services.gateway.data = {
                network = {
                  subnets.lan = {
                    ipv4 = { subnet = "192.168.1.0/24"; gateway = "192.168.1.1"; };
                    ipv6 = { prefix = "2001:db8::/48"; gateway = "2001:db8::1"; };
                  };
                  dhcp = { poolStart = "192.168.1.100"; poolEnd = "192.168.1.200"; };
                };
                hosts = { staticDHCPv4Assignments = []; staticDHCPv6Assignments = []; };
                firewall = {
                  zones = {
                    green = { allowedTCPPorts = [ 22 53 80 443 ]; allowedUDPPorts = [ 53 67 ]; };
                    red = { allowedTCPPorts = []; allowedUDPPorts = []; };
                  };
                };
              };
            }
          ];
        };

        alix-dnsmasq = nixpkgs-stable.lib.nixosSystem {
          system = "i686-linux";
          modules = [
            self.nixosModules.default
            ./hosts/alix.nix
            {
              nixpkgs.overlays = [
                (final: prev: {
                  gateway-health = self.packages."${prev.stdenv.hostPlatform.system}".gateway-health;
                  gateway-setup = self.packages."${prev.stdenv.hostPlatform.system}".gateway-setup;
                })
              ];
              services.gateway.profile = "alix-dnsmasq";
              services.gateway.enable = true;
              services.gateway.network.enable = true;
              services.gateway.interfaces = {
                lan = "eth1";
                wan = "eth0";
              };

              services.gateway.data = {
                network = {
                  subnets.lan = {
                    ipv4 = { subnet = "192.168.1.0/24"; gateway = "192.168.1.1"; };
                    ipv6 = { prefix = "2001:db8::/48"; gateway = "2001:db8::1"; };
                  };
                  dhcp = { poolStart = "192.168.1.100"; poolEnd = "192.168.1.200"; };
                };
                hosts = { staticDHCPv4Assignments = []; staticDHCPv6Assignments = []; };
                firewall = {
                  zones = {
                    green = { allowedTCPPorts = [ 22 53 80 443 ]; allowedUDPPorts = [ 53 67 ]; };
                    red = { allowedTCPPorts = []; allowedUDPPorts = []; };
                  };
                };
              };
            }
          ];
        };
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          branding = import ./branding.nix { inherit pkgs; };

          gateway-health = pkgs.rustPlatform.buildRustPackage {
            pname = "gateway-health";
            version = "0.1.0";
            src = ./tools/gateway-health;
            cargoLock = {
              lockFile = ./tools/gateway-health/Cargo.lock;
            };
          };

          gateway-setup = pkgs.rustPlatform.buildRustPackage {
            pname = "gateway-setup";
            version = "0.1.0";
            src = ./tools/gateway-setup;
            cargoLock = {
              lockFile = ./tools/gateway-setup/Cargo.lock;
            };
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              nixfmt-rfc-style
              nixci
              engram.packages.${system}.default
            ];
            shellHook = ''
              export IN_NIX_SHELL=1
            '';
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Core working tests
          #             # service-mesh-test = import ./tests/service-mesh-test.nix {
          #   inherit pkgs;
          #   inherit (nixpkgs) lib;
          # };
          # cdn-test = import ./tests/cdn-test.nix {
          #   inherit system pkgs;
          # };
          security-core-test = pkgs.testers.nixosTest (
            import ./tests/security-core-test.nix {
              inherit pkgs;
              inherit (nixpkgs) lib;
            }
          );
          basic-gateway-test = import ./tests/basic-gateway-test.nix {
            test-ssh-api = import ./test-ssh-api.nix {
              inherit pkgs;
              inherit (nixpkgs) lib;
            };
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          test-ssh-api = import ./test-ssh-api.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          network-core-test = import ./tests/network-core-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          test-networking-isolated = import ./tests/test-networking-isolated.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          minimal-working-test = import ./tests/minimal-working-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          ultra-minimal-test = pkgs.testers.nixosTest {
            name = "ultra-minimal-test";

            nodes = {
              gateway =
                { config, pkgs, ... }:
                {
                  # Simple test service
                  systemd.services.test-service = {
                    description = "Test Service";
                    wantedBy = [ "multi-user.target" ];
                    serviceConfig = {
                      ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
                    };
                  };

                  environment.systemPackages = with pkgs; [
                    coreutils
                  ];
                };
            };

            testScript = ''
              start_all()

              # Wait for services to start
              gateway.wait_for_unit("multi-user.target")
              gateway.sleep(5)

              # Test that test service is running
              gateway.succeed("systemctl is-active test-service")

              # Test basic functionality
              gateway.succeed("echo 'Ultra minimal test passed!'")

              print("✅ Ultra minimal test passed!")
            '';
          };
          # api-gateway-test = import ./tests/api-gateway-test.nix {
          #   inherit pkgs;
          #   inherit (nixpkgs) lib;
          # };
          # nat-gateway-test = import ./tests/nat-gateway-test.nix {
          #   inherit pkgs;
          #   inherit (nixpkgs) lib;
          # };
          # config-reload-test = import ./tests/config-reload-test.nix {
          #   inherit pkgs;
          #   inherit (nixpkgs) lib;
          # };
          # secrets-management-test = import ./tests/secrets-management-test.nix {
          #   inherit pkgs;
          #   inherit (nixpkgs) lib;
          # };
          backup-recovery-test = import ./tests/backup-recovery-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          disaster-recovery-test = import ./tests/disaster-recovery-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };

          # Core infrastructure tests
          test-evidence = import ./tests/test-evidence.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          dns-comprehensive-test = import ./tests/dns-comprehensive-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          # network-comprehensive-test = import ./tests/network-comprehensive-test.nix {
          #   inherit pkgs;
          #   inherit (nixpkgs) lib;
          # };
          # security-comprehensive-test = import ./tests/security-comprehensive-test.nix {
          #   inherit pkgs;
          #   inherit (nixpkgs) lib;
          # };

          # Feature tests
          # captive-portal-test = import ./tests/captive-portal-test.nix {
          #   inherit pkgs;
          #   inherit (nixpkgs) lib;
          # };
          # adblock-test = import ./tests/adblock-test.nix {
          #   inherit pkgs;
          #   inherit (nixpkgs) lib;
          # };
          # dot1x-test = import ./tests/8021x-test.nix {
          #   inherit pkgs;
          #   inherit (nixpkgs) lib;
          # };

          # Additional tests
          validator-test = import ./tests/validator-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          template-test = import ./tests/template-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          environment-overrides-test = pkgs.testers.nixosTest (
            import ./tests/environment-overrides-test.nix {
              inherit pkgs;
              inherit (nixpkgs) lib;
            }
          );
          secrets-management-test = import ./tests/secrets-management-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          dhcp-basic-test = import ./tests/dhcp-basic-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          config-diff-test = import ./tests/config-diff-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          health-checks-test = import ./tests/health-checks-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          validators-unit-test = import ./tests/validators-unit-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          health-checks-unit-test = import ./tests/health-checks-unit-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          config-reload-unit-test = import ./tests/config-reload-unit-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          cluster-manager-unit-test = import ./tests/cluster-manager-unit-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          bgp-minimal-test = import ./tests/bgp-minimal-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          policy-routing-test = import ./tests/policy-routing-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };

          # Phase 2 Core Networking Tests
          ipv4-ipv6-dual-stack-test = import ./tests/ipv4-ipv6-dual-stack-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          interface-management-failover-test = import ./tests/interface-management-failover-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          routing-ip-forwarding-test = import ./tests/routing-ip-forwarding-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          nat-port-forwarding-test = import ./tests/nat-port-forwarding-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };

          # Phase 3 Advanced Networking Tests
          wireguard-vpn-test = import ./tests/wireguard-automation-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          tailscale-site-to-site-test = import ./tests/tailscale-site-to-site-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          advanced-qos-test = import ./tests/qos-advanced-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          app-aware-qos-test = import ./tests/app-aware-qos-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          device-bandwidth-test = import ./tests/device-bandwidth-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };

          # Phase 4 Security & Monitoring Tests
          zero-trust-test = import ./tests/zero-trust-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          device-posture-test = import ./tests/device-posture-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          threat-intel-test = import ./tests/threat-intel-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          ip-reputation-test = import ./tests/ip-reputation-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          malware-detection-test = import ./tests/malware-detection-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          time-based-access-test = import ./tests/time-based-access-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          log-aggregation-test = import ./tests/log-aggregation-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          health-monitoring-test = import ./tests/health-monitoring-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          topology-discovery-test = import ./tests/topology-discovery-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          performance-baselining-test = import ./tests/performance-baselining-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };

          # Phase 5 Advanced Network Services Tests
          task-01-validation = import ./tests/task-01-validation-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          task-09-bgp-routing = import ./tests/bgp-basic-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          task-10-policy-routing = import ./tests/policy-routing-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          task-22-zero-trust = import ./tests/zero-trust-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          task-45-zero-trust-architecture = import ./tests/zero-trust-architecture-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          task-65-8021x-nac = import ./tests/8021x-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          task-51-xdp-acceleration = import ./tests/xdp-ebpf-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          task-64-vrf-support = import ./tests/vrf-support-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          task-66-sdwan-engineering = import ./tests/sdwan-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          task-67-ipv6-transition = import ./tests/ipv6-transition-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          task-18-log-aggregation = import ./tests/log-aggregation-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          task-31-ha-clustering = import ./tests/ha-cluster-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          task-45-ci-cd-integration = import ./tests/ci-cd-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };

          # Phase 6 Hardware & Infrastructure Tests
          hardware-compatibility-test =
            (import ./tests/hardware-compatibility-test.nix {
              inherit pkgs;
              inherit (nixpkgs) lib;
            }).hardwareCompatibilityTest;

          infrastructure-integration-test =
            (import ./tests/infrastructure-integration-test.nix {
              inherit pkgs;
              inherit (nixpkgs) lib;
            }).containerTest;

          # Phase 6 Cloud Infrastructure Tests
          nat-gateway-test = import ./tests/nat-gateway-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          # task-68-nat-gateway = import ./tests/nat-gateway-test.nix {
          #   inherit pkgs;
          #   inherit (nixpkgs) lib;
          # };
          task-70-internet-gateway = import ./tests/internet-gateway-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };
          task-71-transit-gateway = import ./tests/transit-gateway-test.nix {
            inherit pkgs;
            inherit (nixpkgs) lib;
          };

          # Advanced Acceptance Testing
          automatedAcceptanceTest =
            (import ./tests/automated-acceptance-test.nix {
              inherit pkgs;
              inherit (nixpkgs) lib;
            }).automatedAcceptanceTest;
        }
      );
    };
}
