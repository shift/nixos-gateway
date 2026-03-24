{
  pkgs ? import <nixpkgs> { },
}:
let
  lib = pkgs.lib;
  v = import ../../lib/validators.nix { inherit lib; };
in
pkgs.runCommand "test-validators" { } ''
  # Test IP Validation
  echo "Testing IP Validation..."

  # Valid IPs
  if [ "${toString (v.validateIPAddress "192.168.1.1")}" = "1" ]; then echo "PASS: valid IP 192.168.1.1"; else echo "FAIL: valid IP 192.168.1.1"; exit 1; fi
  if [ "${toString (v.validateIPAddress "10.0.0.1")}" = "1" ]; then echo "PASS: valid IP 10.0.0.1"; else echo "FAIL: valid IP 10.0.0.1"; exit 1; fi
  if [ "${toString (v.validateIPAddress "0.0.0.0")}" = "1" ]; then echo "PASS: valid IP 0.0.0.0"; else echo "FAIL: valid IP 0.0.0.0"; exit 1; fi
  if [ "${toString (v.validateIPAddress "255.255.255.255")}" = "1" ]; then echo "PASS: valid IP 255.255.255.255"; else echo "FAIL: valid IP 255.255.255.255"; exit 1; fi

  # Invalid IPs
  if [ "${toString (v.validateIPAddress "999.999.999.999")}" != "1" ]; then echo "PASS: invalid IP 999.999.999.999"; else echo "FAIL: invalid IP 999.999.999.999"; exit 1; fi
  if [ "${toString (v.validateIPAddress "256.0.0.1")}" != "1" ]; then echo "PASS: invalid IP 256.0.0.1"; else echo "FAIL: invalid IP 256.0.0.1"; exit 1; fi
  if [ "${toString (v.validateIPAddress "192.168.1")}" != "1" ]; then echo "PASS: invalid IP 192.168.1"; else echo "FAIL: invalid IP 192.168.1"; exit 1; fi
  if [ "${toString (v.validateIPAddress "abc")}" != "1" ]; then echo "PASS: invalid IP abc"; else echo "FAIL: invalid IP abc"; exit 1; fi
  if [ "${toString (v.validateIPAddress "")}" != "1" ]; then echo "PASS: invalid IP empty string"; else echo "FAIL: invalid IP empty string"; exit 1; fi
  if [ "${toString (v.validateIPAddress "192.168.1.1.1")}" != "1" ]; then echo "PASS: invalid IP too many octets"; else echo "FAIL: invalid IP too many octets"; exit 1; fi

  echo "IP Validation Tests Passed"

  # Test Port Validation
  echo "Testing Port Validation..."

  # Valid Ports
  if [ "${toString (v.validatePort 80)}" = "1" ]; then echo "PASS: valid Port 80"; else echo "FAIL: valid Port 80"; exit 1; fi
  if [ "${toString (v.validatePort 1)}" = "1" ]; then echo "PASS: valid Port 1"; else echo "FAIL: valid Port 1"; exit 1; fi
  if [ "${toString (v.validatePort 65535)}" = "1" ]; then echo "PASS: valid Port 65535"; else echo "FAIL: valid Port 65535"; exit 1; fi

  # Invalid Ports
  if [ "${toString (v.validatePort 0)}" != "1" ]; then echo "PASS: invalid Port 0"; else echo "FAIL: invalid Port 0"; exit 1; fi
  if [ "${toString (v.validatePort 65536)}" != "1" ]; then echo "PASS: invalid Port 65536"; else echo "FAIL: invalid Port 65536"; exit 1; fi
  if [ "${toString (v.validatePort (-1))}" != "1" ]; then echo "PASS: invalid Port -1"; else echo "FAIL: invalid Port -1"; exit 1; fi

  echo "Port Validation Tests Passed"

  # Test CIDR Validation
  echo "Testing CIDR Validation..."

  # Valid CIDR
  if [ "${toString (v.validateCIDR "192.168.1.0/24")}" = "1" ]; then echo "PASS: valid CIDR 192.168.1.0/24"; else echo "FAIL: valid CIDR 192.168.1.0/24"; exit 1; fi
  if [ "${toString (v.validateCIDR "10.0.0.1/32")}" = "1" ]; then echo "PASS: valid CIDR 10.0.0.1/32"; else echo "FAIL: valid CIDR 10.0.0.1/32"; exit 1; fi
  if [ "${toString (v.validateCIDR "0.0.0.0/0")}" = "1" ]; then echo "PASS: valid CIDR 0.0.0.0/0"; else echo "FAIL: valid CIDR 0.0.0.0/0"; exit 1; fi

  # Invalid CIDR - Bad IP
  if [ "${toString (v.validateCIDR "256.168.1.1/24")}" != "1" ]; then echo "PASS: invalid CIDR IP 256.168.1.1/24"; else echo "FAIL: invalid CIDR IP 256.168.1.1/24"; exit 1; fi
  if [ "${toString (v.validateCIDR "192.168.1/24")}" != "1" ]; then echo "PASS: invalid CIDR IP 192.168.1/24"; else echo "FAIL: invalid CIDR IP 192.168.1/24"; exit 1; fi

  # Invalid CIDR - Bad Prefix
  if [ "${toString (v.validateCIDR "192.168.1.1/33")}" != "1" ]; then echo "PASS: invalid CIDR prefix 33"; else echo "FAIL: invalid CIDR prefix 33"; exit 1; fi
  if [ "${toString (v.validateCIDR "192.168.1.1/-1")}" != "1" ]; then echo "PASS: invalid CIDR prefix -1"; else echo "FAIL: invalid CIDR prefix -1"; exit 1; fi
  if [ "${toString (v.validateCIDR "192.168.1.1/abc")}" != "1" ]; then echo "PASS: invalid CIDR prefix abc"; else echo "FAIL: invalid CIDR prefix abc"; exit 1; fi

  # Invalid CIDR - Format
  if [ "${toString (v.validateCIDR "192.168.1.1")}" != "1" ]; then echo "PASS: invalid CIDR format no slash"; else echo "FAIL: invalid CIDR format no slash"; exit 1; fi
  if [ "${toString (v.validateCIDR "192.168.1.1/24/24")}" != "1" ]; then echo "PASS: invalid CIDR format double slash"; else echo "FAIL: invalid CIDR format double slash"; exit 1; fi

  echo "CIDR Validation Tests Passed"

  touch $out
''
