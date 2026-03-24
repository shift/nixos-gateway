# Template Usage Examples

This directory contains examples of how to use the NixOS Gateway configuration templates.

## Available Templates

1. **base-gateway** - Base template with common functionality
2. **simple-gateway** - Inherits from base, adds basic networking
3. **soho-gateway** - Small office/home office setup
4. **enterprise-gateway** - Enterprise-grade with multi-WAN, VPN, IDS
5. **cloud-edge-gateway** - Cloud edge with container networking
6. **isp-gateway** - ISP-grade with BGP and QoS
7. **iot-gateway** - IoT gateway with device isolation

## Usage Examples

See the individual `.nix` files in this directory for complete examples of how to instantiate each template.

## Template Composition

You can also compose multiple templates to create complex configurations:

```nix
# Compose base-gateway + soho-gateway + enterprise-gateway
composed-config = instantiateComposedTemplate templates [
  "base-gateway"
  "soho-gateway" 
  "enterprise-gateway"
] {
  lanInterface = "eth0";
  wanInterface = "eth1";
  # ... other parameters
}
```