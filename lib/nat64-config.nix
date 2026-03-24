# NAT64 Configuration Library
{ lib, pkgs, ... }:

with lib;

let
  inherit (lib) mkOption types mkEnableOption;

in {
  # NAT64 service configuration generator
  mkNat64Service = nat64Config: ''
    # NAT64 Service Configuration
    # Implementation: ${nat64Config.implementation}
    # Prefix: ${nat64Config.prefix}
    # Pool: ${nat64Config.pool}
    
    # Create NAT64 instance
    ${pkgs.jool}/bin/jool --instance ${nat64Config.implementation} \
      --pool ${nat64Config.pool} \
      --prefix ${nat64Config.prefix} \
      --max-sessions ${toString nat64Config.performance.maxSessions} \
      --timeout ${toString nat64Config.performance.timeout}
    
    # Enable NAT64 in kernel
    echo 1 > /proc/sys/net/netfilter/nf_nat64_ipv6
    
    # Configure logging
    echo "NAT64 service started with prefix ${nat64Config.prefix}"
  '';

  # DNS64 service configuration generator
  mkDns64Service = dns64Config: ''
    # DNS64 Service Configuration
    # Listen: ${lib.concatStringsSep ", " dns64Config.server.listen}
    # Upstream: ${lib.concatStringsSep ", " dns64Config.server.upstream}
    # Prefix: ${dns64Config.prefix}
    
    # Generate BIND configuration for DNS64
    cat > /etc/bind/dns64.conf << EOF
    options {
        directory "/var/cache/bind";
        pid-file "/run/named/named.pid";
        listen-on { ${lib.concatStringsSep "; " dns64Config.server.listen} };
        forwarders { ${lib.concatStringsSep "; " dns64Config.server.upstream} };
        
        # DNS64 synthesis configuration
        dns64 ${dns64Config.prefix};
        
        allow-query { any; };
        allow-recursion { any; };
        allow-update { none; };
        version "no";
        
        # Performance tuning
        max-cache-size 256m;
        max-ncache-ttl 300;
        cleaning-interval 60;
    };
    
    zone "." IN {
        type hint;
        file "/usr/share/dns/root.hints";
    };
    EOF
    
    # Start BIND with DNS64
    exec ${pkgs.bind}/bin/named -c /etc/bind/dns64.conf -u named
    
    echo "DNS64 service started with prefix ${dns64Config.prefix}"
  '';

  # Router advertisement configuration
  mkRadvdConfig = cfg: ''
    # Router Advertisement Configuration
    # Interface: ${ipv6Transition.getRadvdInterface cfg}
    # Prefix: ${cfg.addressing.prefix}
    # Managed: ${if cfg.addressing.routerAdvertisements.managed then "yes" else "no"}
    
    # Basic RA configuration
    interface ${ipv6Transition.getRadvdInterface cfg};
    adv_send_advert on;
    adv_source_link_mtu on;
    adv_home_agent_flag off;
    adv_max_interval 600;
    adv_min_interval 200;
    
    # Prefix information
    prefix ${cfg.addressing.prefix};
    adv_on_link on;
    adv_autonomous on;
    adv_router_addr on;
    
    # DHCPv6 information
    ${lib.optionalString (cfg.addressing.mode == "dhcpv6") ''
      adv_managed_flag on;
      adv_other_config_flag on;
    ''}
    
    # DNS information
    ${lib.optionalString cfg.dns64.server.enable ''
      rdnss ${lib.concatStringsSep ", " cfg.dns64.server.listen};
    ''}
  '';

  # Network configuration commands
  mkNetworkConfig = cfg: ''
    # IPv6 Network Configuration
    # Mode: ${cfg.addressing.mode}
    # Prefix: ${cfg.addressing.prefix}
    
    # Enable IPv6 forwarding
    sysctl -w net.ipv6.conf.all.forwarding=1
    
    # Configure router advertisements
    ${lib.optionalString cfg.addressing.routerAdvertisements.enable ''
      # Enable router advertisement daemon
      sysctl -w net.ipv6.conf.all.accept_ra=2
      sysctl -w net.ipv6.conf.all.accept_ra_defrtr=1
    ''}
    
    # Configure interface addressing
    ${lib.optionalString (cfg.addressing.mode == "slaac") ''
      # Enable SLAAC on all interfaces
      echo "Configuring SLAAC addressing"
    ''}
    
    ${lib.optionalString (cfg.addressing.mode == "dhcpv6") ''
      # Configure DHCPv6 client
      echo "Configuring DHCPv6 addressing"
    ''}
    
    ${lib.optionalString (cfg.addressing.mode == "static") ''
      # Configure static IPv6 addresses
      echo "Configuring static IPv6 addressing"
    ''}
  '';

  # Disable IPv4 on internal interfaces
  mkDisableIPv4 = cfg: ''
    # Disable IPv4 on internal interfaces for IPv6-only network
    ${lib.concatMapStringsSep "\n" (interface: ''
      # Disable IPv4 on ${interface}
      sysctl -w net.ipv4.conf.${interface}.disable_ipv6=0
      ip link set ${interface} up
      ip addr flush dev ${interface}
    '') (ipv6Transition.getInternalInterfaces cfg)}
  '';

  # Get primary interface for services
  getPrimaryInterface = cfg: 
    # Return the first interface or a default
    "eth0";

  # Get internal interfaces for IPv6-only mode
  getInternalInterfaces = cfg:
    # Return list of internal interfaces
    [ "eth0" "eth1" "eth2" ];

  # Static interface configuration
  mkStaticInterfaces = cfg:
    lib.concatMapStringsSep "\n" (interface: ''
      ${interface} = {
        ipv6.addresses = [
          {
            address = "${cfg.addressing.prefix}::1";
            prefixLength = 64;
          }
        ];
      };
    '') (ipv6Transition.getInternalInterfaces cfg);

  # Static interface configuration as attribute set
  mkStaticInterfacesAttributeSet = cfg:
    lib.listToAttrs (map (interface: {
      name = interface;
      value = {
        ipv6.addresses = [
          {
            address = "${cfg.addressing.prefix}::1";
            prefixLength = 64;
          }
        ];
      };
    }) (ipv6Transition.getInternalInterfaces cfg));

  # Monitoring service configuration
  mkMonitoringService = cfg: ''
    # IPv6 Transition Monitoring Service
    # NAT64: ${if cfg.monitoring.nat64.enable then "enabled" else "disabled"}
    # DNS64: ${if cfg.monitoring.dns64.enable then "enabled" else "disabled"}
    
    # Monitor NAT64 performance
    ${lib.optionalString cfg.monitoring.nat64.enable ''
      # NAT64 metrics collection
      while true; do
        # Get NAT64 statistics
        if [ -f /proc/net/netfilter/nf_nat64_ipv6 ]; then
          local sessions=$(cat /proc/net/netfilter/nf_nat64_ipv6)
          echo "$(date): NAT64 sessions: $sessions"
        fi
        
        # Get translation statistics
        local stats=$(${pkgs.jool}/bin/jool --instance ${cfg.nat64.implementation} --stats 2>/dev/null || echo "0")
        echo "$(date): NAT64 stats: $stats"
        
        sleep 30
      done
    ''}
    
    # Monitor DNS64 performance
    ${lib.optionalString cfg.monitoring.dns64.enable ''
      # DNS64 metrics collection
      while true; do
        # Check DNS64 service status
        if pgrep -f "named" > /dev/null; then
          echo "$(date): DNS64 service running"
        else
          echo "$(date): DNS64 service not running"
        fi
        
        # Test DNS64 synthesis
        local test_result=$(${pkgs.dig}/bin/dig @::1 AAAA ipv4only.arpa +short 2>/dev/null || echo "FAILED")
        echo "$(date): DNS64 test: $test_result"
        
        sleep 60
      done
    ''}
  '';

  # Get router advertisement interface
  getRadvdInterface = cfg:
    # Return the primary interface for router advertisements
    ipv6Transition.getPrimaryInterface cfg;

in {
  inherit
    mkNat64Service
    mkDns64Service
    mkRadvdConfig
    mkNetworkConfig 
    mkDisableIPv4 
    getPrimaryInterface 
    getInternalInterfaces 
    mkStaticInterfaces 
    mkMonitoringService 
    getRadvdInterface;
}
