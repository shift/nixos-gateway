# WireGuard VPN Automation

**Status: Completed**

## Description
Implement automated WireGuard VPN configuration with peer management, key rotation, and network integration.

## Requirements

### Current State
- Basic VPN module exists
- Manual peer configuration
- Limited automation capabilities

### Improvements Needed

#### 1. Automated Peer Management
- Dynamic peer addition/removal
- Peer configuration templates
- Bulk peer operations
- Peer health monitoring

#### 2. Key Management
- Automatic key generation
- Key rotation policies
- Secure key distribution
- Key revocation handling

#### 3. Network Integration
- Automatic routing table updates
- DNS configuration for VPN clients
- Firewall rule generation
- Multi-site VPN mesh support

#### 4. Advanced Features
- Site-to-site VPN automation
- Client configuration generation
- VPN performance monitoring
- Split tunneling support

## Implementation Details

### Files to Modify
- `modules/vpn.nix` - Enhance existing VPN module
- `lib/wireguard-manager.nix` - WireGuard automation utilities

### VPN Configuration
```nix
services.gateway.vpn = {
  wireguard = {
    enable = true;
    
    server = {
      interface = "wg0";
      listenPort = 51820;
      address = "10.0.0.1/24";
      privateKey = "encrypted-key";
      
      peers = {
        "site1" = {
          publicKey = "peer-public-key";
          allowedIPs = [ "10.0.0.2/32" "192.168.2.0/24" ];
          endpoint = "site1.example.com:51820";
          persistentKeepalive = 25;
          
          routing = {
            advertiseRoutes = [ "192.168.2.0/24" ];
            acceptRoutes = [ "192.168.3.0/24" ];
          };
        };
        
        "client1" = {
          publicKey = "client-public-key";
          allowedIPs = [ "10.0.0.3/32" ];
          
          clientConfig = {
            dns = [ "10.0.0.1" ];
            splitTunnel = true;
            excludedNetworks = [ "192.168.1.0/24" ];
          };
        };
      };
    };
    
    automation = {
      keyRotation = {
        interval = "90d";
        notifyBefore = "7d";
        automaticRollout = true;
      };
      
      peerManagement = {
        autoAddFromAPI = true;
        healthCheckInterval = "5m";
        removeInactiveAfter = "30d";
      };
      
      routing = {
        autoConfigureRoutes = true;
        redistributeConnected = true;
        bfdSupport = true;
      };
    };
    
    monitoring = {
      enable = true;
      metrics = {
        peerStatus = true;
        trafficStats = true;
        latency = true;
      };
    };
  };
};
```

### Integration Points
- Network module integration
- Firewall module integration
- Monitoring module integration
- Secrets management integration

## Testing Requirements
- Peer connection tests
- Key rotation tests
- Routing validation tests
- Performance tests with multiple peers

## Dependencies
- 07-secrets-management-integration
- 08-secret-rotation-automation

## Estimated Effort
- Medium (WireGuard automation)
- 2 weeks implementation
- 1 week testing

## Success Criteria
- Automatic peer provisioning
- Seamless key rotation
- Proper route distribution
- Comprehensive VPN monitoring
## Implementation Summary (Dec 12 2025)

- Enhanced `modules/vpn.nix` to support:
  - Automated key rotation (systemd timer + script)
  - Dynamic peer management via directory watching (systemd path + watcher service)
  - Auto-generated NAT rules for WAN connectivity
  - Integration with `wg-monitor` script
- Verified with `tests/wireguard-vpn-test.nix`
