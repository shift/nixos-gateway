# Task 13: Advanced QoS Policies - Summary

## Status
**Completed**

## Overview
Implemented a sophisticated Quality of Service (QoS) system capable of application-aware traffic shaping, hierarchical bandwidth management, and strict priority handling.

## Key Components

### 1. Traffic Classification Engine (`lib/traffic-classifier.nix`)
*   **Protocol Mapping**: Utility to map service names (sip, ssh, http) to ports and protocols.
*   **DSCP Handling**: Normalizes DSCP values (EF, AF11, CS0) to standard integers.
*   **Rule Generation**:
    *   Generates `nftables` mangle rules to mark packets (`fwmark`) based on protocols and set DSCP values.
    *   Generates `tc` (Traffic Control) HTB class hierarchies for bandwidth management.

### 2. QoS Module (`modules/qos.nix`)
*   **Configuration**:
    *   `trafficClasses`: Define classes like "voip", "gaming", "bulk" with priorities, bandwidth limits (guaranteed/max), and protocol matches.
    *   `interfaceSpeeds`: Define upload/download limits per interface.
*   **Implementation**:
    *   Uses **HTB (Hierarchical Token Bucket)** for root bandwidth shaping (Egress).
    *   Uses **IFB (Intermediate Functional Block)** to shape Ingress traffic (Download).
    *   Uses **CAKE** as the leaf qdisc for active queue management (bufferbloat mitigation).
    *   Integrates with **nftables** to mark packets in the `forward` hook.
*   **System Integration**:
    *   Service `qos-setup` applies the rules on startup and cleans them up on stop.

### 3. Verification (`tests/qos-test.nix`)
*   Verifies the creation of the HTB/CAKE hierarchy on WAN interfaces.
*   Verifies `nftables` rules are generated correctly for defined classes (VoIP/SIP, Bulk/SSH).
*   Simulates traffic flow to ensure packet marking logic is active (checked via rule existence and qdisc stats).

## Usage Example

```nix
services.gateway.qos = {
  enable = true;
  interfaceSpeeds.wan = { upload = "100Mbit"; download = "1Gbit"; };
  
  trafficClasses = {
    voip = {
      priority = 1; # Highest
      maxBandwidth = "10Mbit";
      guaranteedBandwidth = "5Mbit";
      protocols = [ "sip" "rtp" ];
      dscp = "EF";
    };
    bulk = {
      priority = 5; # Lowest
      maxBandwidth = "500Mbit";
      protocols = [ "ssh" "ftp" ];
    };
  };
};
```

## Next Steps
*   Extend traffic classifier with Layer 7 DPI capabilities (Task 14).
*   Add dynamic bandwidth allocation based on active device count (Task 15).
