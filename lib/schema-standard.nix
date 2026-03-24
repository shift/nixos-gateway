# Standardized Data Schema for NixOS Gateway

This document defines the standardized schema format that all modules should use.

## Network Schema

### Standard Format (New Schema)
```nix
network = {
  subnets = [
    {
      name = "lan";
      network = "192.168.1.0/24";
      gateway = "192.168.1.1";
      ipv4 = {
        subnet = "192.168.1.0/24";
        gateway = "192.168.1.1";
      };
      ipv6 = {
        prefix = "2001:db8::/48";
        gateway = "2001:db8::1";
      };
      dhcpRange = {
        start = "192.168.1.50";
        end = "192.168.1.254";
      };
      dnsServers = ["192.168.1.1"];
      ntpServers = ["192.168.1.1"];
    }
  ];
  mgmtAddress = "192.168.1.1";
}
```

### Legacy Format (Old Schema)
```nix
network = {
  subnets = {
    lan = {
      ipv4 = {
        subnet = "192.168.1.0/24";
        gateway = "192.168.1.1";
      };
      ipv6 = {
        prefix = "2001:db8::/48";
        gateway = "2001:db8::1";
      };
    };
  };
  dhcp = {
    poolStart = "192.168.1.50";
    poolEnd = "192.168.1.254";
  };
  mgmtAddress = "192.168.1.1";
}
```

## Hosts Schema

### Standard Format
```nix
hosts = {
  staticDHCPv4Assignments = [
    {
      name = "server1";
      macAddress = "aa:bb:cc:dd:ee:01";
      ipAddress = "192.168.1.10";
      type = "server";
      fqdn = "server1.lan.local";  # Optional
      ptrRecord = true;           # Optional
    }
  ];
  staticDHCPv6Assignments = [
    {
      name = "server1";
      duid = "00:01:00:01:2a:be:8d:c8:aa:bb:cc:dd:ee:01";
      address = "2001:db8::10";
    }
  ];
}
```

## Migration Strategy

1. **Backward Compatibility**: All modules must support both old and new schemas
2. **Priority**: New schema takes precedence when both are present
3. **Deprecation**: Old schema support will be removed in future versions
4. **Migration Path**: Automatic conversion functions available