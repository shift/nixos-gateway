{
  pkgs,
  lib,
  config,
  ...
}:

let
  validatorScript = ''
    import argparse
    import json
    import sys
    import ipaddress
    import os
    import subprocess

    class Colors:
        HEADER = '\033[95m'
        OKBLUE = '\033[94m'
        OKGREEN = '\033[92m'
        WARNING = '\033[93m'
        FAIL = '\033[91m'
        ENDC = '\033[0m'
        BOLD = '\033[1m'
        UNDERLINE = '\033[4m'

    def log_info(msg):
        print(f"{Colors.OKBLUE}[INFO]{Colors.ENDC} {msg}")

    def log_success(msg):
        print(f"{Colors.OKGREEN}[PASS]{Colors.ENDC} {msg}")

    def log_warning(msg):
        print(f"{Colors.WARNING}[WARN]{Colors.ENDC} {msg}")

    def log_error(msg):
        print(f"{Colors.FAIL}[FAIL]{Colors.ENDC} {msg}")

    def validate_ip(ip):
        try:
            ipaddress.ip_address(ip)
            return True
        except ValueError:
            return False

    def validate_cidr(cidr):
        try:
            ipaddress.ip_network(cidr, strict=False)
            return True
        except ValueError:
            return False

    def check_gateway_config(config_path):
        log_info(f"Validating configuration at: {config_path}")
        
        try:
            # If it's a nix file, try to eval it. If json, load it.
            if config_path.endswith('.nix'):
                 # This is a simplified check, assuming we are running in an environment where we can eval
                 # Or we might just expect a JSON dump passed to this tool.
                 # For the module, we will dump the system config to JSON.
                 pass
            
            with open(config_path, 'r') as f:
                config = json.load(f)
        except Exception as e:
            log_error(f"Failed to load config: {e}")
            return False

        errors = 0
        warnings = 0

        # 1. Validate Networks
        networks = config.get('networking', {}).get('interfaces', {})
        for name, iface in networks.items():
            ipv4_addrs = iface.get('ipv4', {}).get('addresses', [])
            for addr in ipv4_addrs:
                ip = addr.get('address')
                if not validate_ip(ip):
                    log_error(f"Interface {name}: Invalid IP address '{ip}'")
                    errors += 1
                else:
                    log_success(f"Interface {name}: IP {ip} valid")

        # 2. Validate Services (Generic checks)
        services = config.get('services', {})
        if services.get('openssh', {}).get('enable') and services.get('openssh', {}).get('permitRootLogin') == 'yes':
             log_warning("SSH: PermitRootLogin is set to 'yes'. Recommended: 'prohibit-password' or 'no'.")
             warnings += 1

        # 3. Check for Empty Configurations (Potential missing imports)
        if not networks:
            log_warning("Networking: No interfaces defined.")
            warnings += 1

        print("\n" + "="*30)
        print(f"Validation Complete.")
        print(f"Errors: {Colors.FAIL}{errors}{Colors.ENDC}")
        print(f"Warnings: {Colors.WARNING}{warnings}{Colors.ENDC}")
        
        return errors == 0

    if __name__ == "__main__":
        parser = argparse.ArgumentParser(description="NixOS Gateway Configuration Validator")
        parser.add_argument("--config", help="Path to JSON configuration dump", required=True)
        args = parser.parse_args()
        
        if not check_gateway_config(args.config):
            sys.exit(1)
        sys.exit(0)
  '';

  validatorBin = pkgs.writeScriptBin "gateway-validator" ''
    #!${pkgs.python3}/bin/python3
    ${validatorScript}
  '';

in
{
  config = {
    environment.systemPackages = [ validatorBin ];

    # Helper to dump current system config for validation
    # We filter the config to avoid infinite recursion and huge file sizes
    system.build.configJson = pkgs.writeText "system-config.json" (
      builtins.toJSON {
        networking = {
          # Only dump specific interface properties that we know are safe and needed
          interfaces = lib.mapAttrs (name: iface: {
            ipv4 = iface.ipv4;
            ipv6 = iface.ipv6;
          }) config.networking.interfaces;
        };
        services = {
          openssh = config.services.openssh or { };
        };
      }
    );

    environment.shellAliases = {
      "validate-system" = "gateway-validator --config ${
        pkgs.writeText "system-config.json" (
          builtins.toJSON {
            networking = {
              interfaces = lib.mapAttrs (name: iface: {
                ipv4 = iface.ipv4;
                ipv6 = iface.ipv6;
              }) config.networking.interfaces;
            };
            services = {
              openssh = config.services.openssh or { };
            };
          }
        )
      }";
    };
  };
}
