{ features, networkConfig, template ? "basic" }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "simulator-orchestrator";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    nix
    qemu
    openssh
    curl
    jq
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/simulator-orchestrator << 'EOF'
    #!/bin/bash
    set -euo pipefail

    # Configuration
    FEATURES="${lib.concatStringsSep " " features}"
    NETWORK_CONFIG='${builtins.toJSON networkConfig}'
    TEMPLATE="${template}"
    STATE_DIR="/var/lib/simulator"
    LOG_DIR="$STATE_DIR/logs"

    # Logging
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/simulator.log"
    }

    # VM Management Functions
    start_vm() {
        local vm_name="$1"
        local config_file="$2"

        log "Starting VM: $vm_name"

        # Create VM directory
        mkdir -p "$STATE_DIR/vms/$vm_name"

        # Generate NixOS configuration
        cat > "$STATE_DIR/vms/$vm_name/configuration.nix" << VMCONFIG
    { config, pkgs, ... }:
    {
      imports = [ <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix> ];

      virtualisation = {
        memorySize = 2048;
        cores = 2;
        graphics = false;
        qemu.options = [
          "-device virtio-net-pci,netdev=lan0"
          "-netdev bridge,id=lan0,br=simulator-br0"
        ];
      };

      services.openssh.enable = true;
      users.users.root.password = "simulator";

      # Load gateway modules
      imports = [ ./gateway-config.nix ];

      # Network configuration
      networking = {
        useDHCP = false;
        interfaces.eth0.useDHCP = true;
        nameservers = [ "192.168.1.1" ];
      };
    }
    VMCONFIG

        # Copy gateway configuration
        cp "$config_file" "$STATE_DIR/vms/$vm_name/gateway-config.nix"

        # Build and run VM
        nix-build '<nixpkgs/nixos>' \
          --arg configuration "$STATE_DIR/vms/$vm_name/configuration.nix" \
          -o "$STATE_DIR/vms/$vm_name/result" \
          --no-out-link

        # Start VM in background with network isolation
        (
            cd "$STATE_DIR/vms/$vm_name"
            "$STATE_DIR/vms/$vm_name/result/bin/run-nixos-vm" &
            echo $! > "$STATE_DIR/vms/$vm_name/pid"
        )

        log "VM $vm_name started with PID $(cat "$STATE_DIR/vms/$vm_name/pid")"
    }

    stop_vm() {
        local vm_name="$1"

        if [[ -f "$STATE_DIR/vms/$vm_name/pid" ]]; then
            local pid=$(cat "$STATE_DIR/vms/$vm_name/pid")
            log "Stopping VM: $vm_name (PID: $pid)"
            kill "$pid" 2>/dev/null || true
            rm -f "$STATE_DIR/vms/$vm_name/pid"
        fi
    }

    reset_vm() {
        local vm_name="$1"
        log "Resetting VM: $vm_name"
        stop_vm "$vm_name"
        sleep 2
        start_vm "$vm_name" "$STATE_DIR/vms/$vm_name/gateway-config.nix"
    }

    # Network setup functions
    setup_network() {
        log "Setting up simulator network bridge"

        # Create bridge if it doesn't exist
        if ! ip link show simulator-br0 >/dev/null 2>&1; then
            ip link add name simulator-br0 type bridge
            ip link set simulator-br0 up
            ip addr add 192.168.1.1/24 dev simulator-br0
        fi

        # Enable IP forwarding
        echo 1 > /proc/sys/net/ipv4/ip_forward

        # Setup NAT for internet access
        iptables -t nat -A POSTROUTING -o $(ip route show default | awk '{print $5}') -j MASQUERADE
        iptables -A FORWARD -i simulator-br0 -o $(ip route show default | awk '{print $5}') -j ACCEPT
        iptables -A FORWARD -i $(ip route show default | awk '{print $5}') -o simulator-br0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    }

    teardown_network() {
        log "Tearing down simulator network"

        # Remove iptables rules
        iptables -t nat -D POSTROUTING -o $(ip route show default | awk '{print $5}') -j MASQUERADE 2>/dev/null || true
        iptables -D FORWARD -i simulator-br0 -o $(ip route show default | awk '{print $5}') -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -i $(ip route show default | awk '{print $5}') -o simulator-br0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

        # Remove bridge
        ip link set simulator-br0 down 2>/dev/null || true
        ip link delete simulator-br0 2>/dev/null || true
    }

    isolate_network() {
        local vm_name="$1"
        log "Isolating network for VM: $vm_name"

        # Disconnect VM from bridge (would need more complex setup)
        # For now, just log the intention
        log "Network isolation requested for $vm_name - feature needs implementation"
    }

    connect_network() {
        local vm_name="$1"
        log "Connecting network for VM: $vm_name"

        # Reconnect VM to bridge
        log "Network connection requested for $vm_name - feature needs implementation"
    }

    # Main loop
    log "Interactive VM Simulator Orchestrator started"
    log "Features: $FEATURES"
    log "Network Config: $NETWORK_CONFIG"

    # Setup network
    setup_network

    # Cleanup on exit
    trap teardown_network EXIT

    # Load template
    load_template() {
        local template="$1"
        case "$template" in
            "basic")
                cat << 'TEMPLATE'
{ config, lib, ... }:
{
  services.gateway = {
    enable = true;
    interfaces = {
      lan = "eth0";
      wan = "eth1";
    };
  };
}
TEMPLATE
                ;;
            "networking")
                cat << 'TEMPLATE'
{ config, lib, ... }:
{
  services.gateway = {
    enable = true;
    interfaces = {
      lan = "eth0";
      wan = "eth1";
      dmz = "eth2";
    };
    features = [ "routing" "nat" "dhcp" "dns" ];
  };
}
TEMPLATE
                ;;
            "security")
                cat << 'TEMPLATE'
{ config, lib, ... }:
{
  services.gateway = {
    enable = true;
    interfaces = {
      lan = "eth0";
      wan = "eth1";
    };
    features = [ "firewall" "ids" "vpn" "zero-trust" ];
  };
}
TEMPLATE
                ;;
            "monitoring")
                cat << 'TEMPLATE'
{ config, lib, ... }:
{
  services.gateway = {
    enable = true;
    interfaces = {
      lan = "eth0";
      wan = "eth1";
    };
    features = [ "monitoring" "logging" "tracing" "health-checks" ];
  };
}
TEMPLATE
                ;;
            "full")
                cat << 'TEMPLATE'
{ config, lib, ... }:
{
  services.gateway = {
    enable = true;
    interfaces = {
      lan = "eth0";
      wan = "eth1";
      dmz = "eth2";
      mgmt = "eth3";
    };
    features = [ "routing" "nat" "dhcp" "dns" "firewall" "ids" "vpn" "zero-trust" "monitoring" "logging" "tracing" "health-checks" "load-balancing" "qos" "backup" "ha" ];
  };
}
TEMPLATE
                ;;
        esac
    }

    # Create initial gateway configuration
    mkdir -p "$STATE_DIR/configs"
    load_template "$TEMPLATE" > "$STATE_DIR/configs/gateway.nix"

    # If custom features specified, create enhanced config
    if [[ -n "$FEATURES" ]]; then
        cat >> "$STATE_DIR/configs/gateway.nix" << EOF
# Custom features overlay
{ config, lib, ... }:
{
  services.gateway.features = lib.mkForce [ $FEATURES ];
}
EOF
    fi

    # Start initial VM
    start_vm "gateway-1" "$STATE_DIR/configs/gateway.nix"

    # Keep running and handle commands
    while true; do
        sleep 10

        # Check VM health
        if [[ -f "$STATE_DIR/vms/gateway-1/pid" ]]; then
            local pid=$(cat "$STATE_DIR/vms/gateway-1/pid")
            if ! kill -0 "$pid" 2>/dev/null; then
                log "VM gateway-1 died, restarting..."
                start_vm "gateway-1" "$STATE_DIR/configs/gateway.nix"
            fi
        fi
    done
    EOF

    chmod +x $out/bin/simulator-orchestrator
  '';
}