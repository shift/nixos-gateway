# AWS NAT Gateway Replacement

**Status: Pending**

## Description
Implement a drop-in replacement for AWS NAT Gateway functionality, providing Source NAT (SNAT) capabilities for private subnet internet access with enterprise-grade features and cost optimization.

## Requirements

### Current State
- Basic NAT64/DNS64 support exists for IPv6 transition
- VRF-aware NAT mentioned but not fully implemented
- No dedicated NAT Gateway equivalent for IPv4 outbound access

### Improvements Needed

#### 1. SNAT Implementation
- Source Network Address Translation for outbound traffic
- Configurable NAT instance pools with multiple public IPs
- Connection tracking and state management
- Port address translation (PAT) for efficient IP usage

#### 2. NAT Gateway Management
- Multiple NAT instances for high availability
- Automatic failover between NAT instances
- Load balancing across NAT pools
- Bandwidth monitoring and utilization tracking

#### 3. Security Integration
- NAT rules integrated with firewall policies
- Source IP preservation options
- NAT traversal for VPN and VoIP protocols
- DDoS protection at NAT layer

#### 4. Performance Optimization
- Kernel-level NAT processing
- Connection table optimization
- Memory-efficient state tracking
- CPU utilization monitoring

#### 5. Monitoring and Observability
- NAT connection statistics
- Bandwidth usage per NAT instance
- Error rate monitoring
- Integration with Prometheus metrics

## Implementation Details

### Files to Create/Modify
- `modules/nat-gateway.nix` - Main NAT Gateway module
- `lib/nat-config.nix` - NAT configuration utilities
- `lib/nat-monitoring.nix` - NAT monitoring and metrics

### NAT Gateway Configuration Structure
```nix
services.gateway.natGateway = {
  enable = true;
  
  instances = [
    {
      name = "nat-primary";
      publicInterface = "eth0";
      privateSubnets = ["10.0.1.0/24" "10.0.2.0/24"];
      publicIPs = ["203.0.113.10" "203.0.113.11"];
      
      # Performance tuning
      maxConnections = 100000;
      timeout = {
        tcp = "24h";
        udp = "300s";
      };
      
      # Security
      allowInbound = false;
      portForwarding = [
        {
          protocol = "tcp";
          port = 80;
          targetIP = "10.0.1.100";
          targetPort = 8080;
        }
      ];
    }
  ];
  
  # Global settings
  monitoring = {
    enable = true;
    prometheusPort = 9092;
  };
};
```

### Technical Specifications
- **Protocols**: IPv4 NAT (RFC 3022), IPv6 NAT (RFC 6296)
- **Performance**: 10Gbps+ throughput with proper hardware
- **Scalability**: Support for 100k+ concurrent connections
- **Compatibility**: Linux netfilter/iptables backend

### Testing Requirements
- NAT functionality tests with various protocols
- Connection tracking accuracy
- Performance benchmarking under load
- Failover testing between NAT instances
- Security validation (no unauthorized access)

### Success Criteria
- Full AWS NAT Gateway feature parity
- 99.9% uptime for production deployments
- <1% performance degradation vs direct routing
- Comprehensive monitoring and alerting
- Easy migration path from AWS NAT Gateway

### Business Value
- **Cost Savings**: Eliminate AWS NAT Gateway hourly charges ($0.045/hour) and data processing fees
- **Control**: Full visibility and control over NAT operations
- **Flexibility**: Custom NAT policies and advanced features not available in AWS
- **Performance**: Optimized for specific workloads and hardware

### Dependencies
- Requires network interface management
- Integrates with firewall and routing modules
- Uses existing monitoring infrastructure

### Effort Estimate
- **Complexity**: High (new module development)
- **Timeline**: 4-6 weeks
- **Team**: 2 developers (networking + NixOS expert)
- **Risk**: Medium (netfilter integration complexity)

### Migration Guide
Include detailed steps for migrating from AWS NAT Gateway:
1. Identify NAT Gateway usage patterns
2. Configure equivalent NAT instances
3. Update route tables and security groups
4. Test connectivity and performance
5. Cutover with minimal downtime