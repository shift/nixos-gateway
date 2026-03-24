# 802.1X Network Access Control (NAC)

**Status: Pending**

## Description
Implement 802.1X Network Access Control for identity-aware networking with dynamic VLAN assignment based on user authentication.

## Requirements

### Current State
- MAC address whitelists for device access
- Static VLAN assignments per port
- No user authentication for network access
- Vulnerable to MAC spoofing attacks

### Improvements Needed

#### 1. 802.1X Authentication Framework
- RADIUS server integration (FreeRADIUS)
- EAP-TLS certificate-based authentication
- PEAP-MSCHAPv2 password authentication
- Dynamic VLAN assignment based on user identity

#### 2. Switch Configuration Management
- 802.1X port configuration
- RADIUS server settings
- Guest VLAN assignment for unauthenticated devices
- Failed authentication handling

#### 3. Certificate Management
- User certificate generation and management
- CA certificate management
- Certificate revocation checking
- Integration with secrets management

#### 4. Dynamic VLAN Assignment
- User-to-VLAN mapping
- Role-based network access
- Time-based access controls
- Device posture assessment integration

## Implementation Details

### Files to Create
- `modules/8021x.nix` - 802.1X NAC module
- `modules/freeradius.nix` - RADIUS server module
- `lib/nac-config.nix` - NAC configuration functions
- `lib/eap-certificates.nix` - Certificate management

### New Configuration Options
```nix
accessControl.nac = {
  enable = lib.mkEnableOption "802.1X Network Access Control";
  
  radius = {
    enable = lib.mkEnableOption "RADIUS server";
    
    server = {
      host = lib.mkOption {
        type = lib.types.str;
        description = "RADIUS server address";
      };
      
      port = lib.mkOption {
        type = lib.types.port;
        default = 1812;
        description = "RADIUS authentication port";
      };
      
      secret = lib.mkOption {
        type = lib.types.str;
        description = "RADIUS shared secret";
      };
    };
    
    authentication = {
      methods = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [ "eap-tls" "peap" "ttls" ]);
        default = [ "eap-tls" "peap" ];
        description = "Allowed EAP authentication methods";
      };
      
      certificates = {
        caCert = lib.mkOption {
          type = lib.types.path;
          description = "CA certificate for EAP-TLS";
        };
        
        serverCert = lib.mkOption {
          type = lib.types.path;
          description = "RADIUS server certificate";
        };
        
        serverKey = lib.mkOption {
          type = lib.types.path;
          description = "RADIUS server private key";
        };
      };
    };
  };
  
  ports = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        enable = lib.mkEnableOption "802.1X on this port";
        
        mode = lib.mkOption {
          type = lib.types.enum [ "auto" "force-authorized" "force-unauthorized" ];
          default = "auto";
          description = "Port control mode";
        };
        
        reauthTimeout = lib.mkOption {
          type = lib.types.int;
          default = 3600;
          description = "Re-authentication timeout in seconds";
        };
        
        maxAttempts = lib.mkOption {
          type = lib.types.int;
          default = 3;
          description = "Maximum authentication attempts";
        };
        
        guestVlan = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          description = "VLAN for unauthenticated devices";
        };
        
        unauthorizedVlan = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          description = "VLAN for failed authentication";
        };
      };
    });
    description = "802.1X port configuration";
  };
  
  users = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        username = lib.mkOption {
          type = lib.types.str;
          description = "RADIUS username";
        };
        
        password = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          description = "Password for PEAP/TTLS";
        };
        
        certificate = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          description = "Client certificate for EAP-TLS";
        };
        
        vlan = lib.mkOption {
          type = lib.types.int;
          description = "Assigned VLAN";
        };
        
        groups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "User groups for role-based access";
        };
        
        accessTimes = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "Time-based access restrictions";
        };
      };
    });
    description = "NAC user definitions";
  };
  
  policies = {
    defaultVlan = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Default VLAN for authenticated users";
    };
    
    guestVlan = lib.mkOption {
      type = lib.types.int;
      default = 999;
      description = "VLAN for guest access";
    };
    
    quarantineVlan = lib.mkOption {
      type = lib.types.int;
      default = 998;
      description = "VLAN for quarantined devices";
    };
  };
};
```

### Integration Points
- Switch configuration for 802.1X support
- Secrets management for certificates and passwords
- VLAN management for dynamic assignment
- Monitoring for authentication events

## Testing Requirements
- EAP-TLS certificate authentication
- PEAP-MSCHAPv2 password authentication
- Dynamic VLAN assignment
- Failed authentication handling
- Guest access scenarios

## Dependencies
- FreeRADIUS server
- Hostapd with 802.1X support
- Switches with 802.1X capability
- Certificate authority for user certificates

## Estimated Effort
- High (complex authentication system)
- 4-5 weeks implementation
- 3 weeks testing and security validation

## Success Criteria
- Successful EAP-TLS authentication
- Dynamic VLAN assignment working
- Guest access functional
- No unauthorized network access
- Comprehensive logging and monitoring