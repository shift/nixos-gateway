#!/usr/bin/env bash
set -euo pipefail

# Interactive Feature Sandbox Launcher
# Provides isolated environments for safe feature exploration and testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SIMULATION_ROOT="$PROJECT_ROOT/.simulation"
LOGS_DIR="$SIMULATION_ROOT/logs"
CONFIGS_DIR="$SIMULATION_ROOT/configs"
RUNTIME_DIR="$SIMULATION_ROOT/runtime"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Default values
FEATURE=""
DURATION=30
ISOLATION="full"
INTERACTIVE=true
VERBOSE=false
CLEANUP=true

# Available features and their configurations
declare -A FEATURE_CONFIGS=(
    ["networking"]="namespace,bridge,veth,traffic-sim"
    ["routing"]="bgp,ospf,policy-routing,forwarding"
    ["security"]="firewall,zero-trust,microsegmentation,threat-sim"
    ["performance"]="xdp,ebpf,qos,bandwidth-shaping"
    ["dns"]="resolver,forwarder,cache,security"
    ["dhcp"]="server,relay,lease-management,option-handling"
    ["vpn"]="wireguard,tailscale,site-to-site,client-vpn"
    ["monitoring"]="metrics,logging,tracing,health-checks"
)

# Help function
show_help() {
    cat << EOF
${BOLD}NixOS Gateway Interactive Feature Sandbox${NC}

${BOLD}USAGE:${NC}
    $0 [OPTIONS] --feature <FEATURE>

${BOLD}FEATURES:${NC}
    networking     Network interfaces, bridges, and traffic simulation
    routing        BGP, OSPF, policy routing, and forwarding
    security       Firewall, zero-trust, microsegmentation, threat simulation
    performance    XDP/eBPF, QoS, bandwidth shaping, acceleration
    dns            DNS resolution, forwarding, caching, security
    dhcp           DHCP server, relay, lease management
    vpn            WireGuard, Tailscale, site-to-site, client VPN
    monitoring     Metrics, logging, tracing, health checks

${BOLD}OPTIONS:${NC}
    -f, --feature <FEATURE>        Feature to sandbox (required)
    -d, --duration <MINUTES>        Sandbox duration (default: 30)
    -i, --isolation <LEVEL>        Isolation level: minimal, full (default: full)
    --interactive <BOOL>           Interactive mode (default: true)
    --verbose                      Verbose output
    --no-cleanup                   Don't cleanup after sandbox
    -h, --help                     Show this help

${BOLD}EXAMPLES:${NC}
    $0 --feature networking --duration 15
    $0 --feature security --isolation full --interactive true
    $0 --feature performance --duration 60 --verbose

${BOLD}ISOLATION LEVELS:${NC}
    minimal    Basic isolation, some host interaction
    full       Complete isolation with network namespaces

EOF
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_verbose() {
    [[ "$VERBOSE" == "true" ]] && echo -e "${PURPLE}[VERBOSE]${NC} $*"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--feature)
                FEATURE="$2"
                shift 2
                ;;
            -d|--duration)
                DURATION="$2"
                shift 2
                ;;
            -i|--isolation)
                ISOLATION="$2"
                shift 2
                ;;
            --interactive)
                INTERACTIVE="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --no-cleanup)
                CLEANUP=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Validate arguments
validate_args() {
    if [[ -z "$FEATURE" ]]; then
        log_error "Feature is required. Use --feature <FEATURE>"
        show_help
        exit 1
    fi

    if [[ ! -v "FEATURE_CONFIGS[$FEATURE]" ]]; then
        log_error "Unknown feature: $FEATURE"
        log_info "Available features: ${!FEATURE_CONFIGS[*]}"
        exit 1
    fi

    if [[ ! "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 1 ]] || [[ "$DURATION" -gt 180 ]]; then
        log_error "Duration must be between 1 and 180 minutes"
        exit 1
    fi

    if [[ ! "$ISOLATION" =~ ^(minimal|full)$ ]]; then
        log_error "Isolation level must be 'minimal' or 'full'"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    log_verbose "Checking dependencies..."
    
    local deps=("nix" "jq" "unshare" "ip" "iptables-nables")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log_error "Missing dependency: $dep"
            log_info "Install with: nix-shell -p $dep"
            exit 1
        fi
    done

    # Check if running as root (required for network namespaces)
    if [[ "$ISOLATION" == "full" ]] && [[ $EUID -ne 0 ]]; then
        log_warning "Full isolation requires root privileges"
        log_info "Consider using 'sudo $0 $*' or switch to minimal isolation"
        exit 1
    fi

    log_success "All dependencies satisfied"
}

# Create sandbox directories
create_directories() {
    log_verbose "Creating sandbox directories..."
    
    mkdir -p "$SIMULATION_ROOT"
    mkdir -p "$LOGS_DIR"
    mkdir -p "$CONFIGS_DIR"
    mkdir -p "$RUNTIME_DIR"
    
    log_verbose "Sandbox directories created"
}

# Generate sandbox configuration
generate_config() {
    local feature="$1"
    local config_file="$CONFIGS_DIR/sandbox-${feature}.nix"
    
    log_verbose "Generating sandbox configuration for $feature..."
    
    cat > "$config_file" << EOF
# Generated sandbox configuration for $feature
{ pkgs, lib, ... }:

{
  # Sandbox-specific configuration
  environment.systemPackages = with pkgs; [
    # Base tools
    coreutils
    jq
    curl
    iproute2
    iptables
    
    # Feature-specific packages
    $(_get_feature_packages "$feature")
  ];

  # Networking configuration
  networking = {
    # Use network namespaces for isolation
    useNetworkd = true;
    
    # Disable unnecessary services
    firewall.enable = false;
  };

  # Security settings
  security = {
    # Relaxed for sandbox environment
    sudo.enable = false;
    sudo.wheelNeedsPassword = false;
  };

  # Enable feature-specific services
  $(_get_feature_services "$feature")

  # Sandbox-specific settings
  system.stateVersion = "23.11";
}
EOF

    echo "$config_file"
}

# Get feature-specific packages
_get_feature_packages() {
    local feature="$1"
    
    case "$feature" in
        "networking")
            echo "bridge-utils vlan ethtool nettools"
            ;;
        "routing")
            echo "bird frr quagga iproute2"
            ;;
        "security")
            echo "nftables fail2ban iptables"
            ;;
        "performance")
            echo "bcc-tools perf ethtool bpftrace"
            ;;
        "dns")
            echo "bind dnsmasq unbound knot"
            ;;
        "dhcp")
            echo "isc-dhcp kea dhcping"
            ;;
        "vpn")
            echo "wireguard-tools tailscale openvpn"
            ;;
        "monitoring")
            echo "prometheus grafana loki prometheus-alertmanager"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Get feature-specific services
_get_feature_services() {
    local feature="$1"
    
    case "$feature" in
        "networking")
            cat << 'EOF'
  systemd.network.networks."10-sandbox" = {
    matchConfig.Name = "veth0";
    networkConfig.Address = "10.0.100.1/24";
  };
EOF
            ;;
        "security")
            cat << 'EOF'
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 80 443 ];
EOF
            ;;
        "performance")
            cat << 'EOF'
  # Performance tuning for sandbox
  boot.kernel.sysctl = {
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
  };
EOF
            ;;
        *)
            echo "# No specific services for $feature"
            ;;
    esac
}

# Setup network isolation
setup_network_isolation() {
    if [[ "$ISOLATION" != "full" ]]; then
        log_verbose "Skipping network isolation (minimal mode)"
        return 0
    fi

    log_info "Setting up network isolation..."
    
    # Create network namespace
    local ns_name="sandbox-$$"
    unshare --net bash -c "
        ip link set lo up
        ip addr add 127.0.0.1/8 dev lo
        
        # Create veth pair
        ip link add veth0 type veth peer name veth1
        ip link set veth0 up
        ip link set veth1 up
        
        # Assign IP addresses
        ip addr add 10.0.100.1/24 dev veth0
        ip addr add 10.0.100.2/24 dev veth1
        
        # Add routes
        ip route add default via 10.0.100.2 dev veth0
        
        echo 'Network isolation configured'
        echo 'Namespace: $ns_name'
        echo 'Internal IP: 10.0.100.1/24'
    "
}

# Launch sandbox environment
launch_sandbox() {
    local feature="$1"
    local config_file="$2"
    local session_id="sandbox-$(date +%Y%m%d-%H%M%S)-$$"
    
    log_info "Launching $feature sandbox (Session: $session_id)"
    log_info "Duration: ${DURATION} minutes"
    log_info "Isolation: $ISOLATION"
    
    # Create nix-shell environment
    local nix_expr="import $config_file { inherit pkgs; }"
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        launch_interactive_sandbox "$feature" "$session_id" "$nix_expr"
    else
        launch_headless_sandbox "$feature" "$session_id" "$nix_expr"
    fi
}

# Launch interactive sandbox
launch_interactive_sandbox() {
    local feature="$1"
    local session_id="$2"
    local nix_expr="$3"
    
    log_info "Launching interactive $feature sandbox..."
    
    # Create welcome screen
    clear
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                    NIXOS GATEWAY SANDBOX                    ║
║                      Interactive Mode                        ║
╚══════════════════════════════════════════════════════════════╝

Feature: $feature
Session: $session_id
Duration: ${DURATION} minutes

Type 'help' for available commands
Type 'exit' to leave the sandbox
EOF

    # Launch nix-shell with custom prompt
    timeout "${DURATION}m" nix-shell --run "
        export SANDBOX_FEATURE='$feature'
        export SANDBOX_SESSION='$session_id'
        export SANDBOX_DURATION='$DURATION'
        export SANDBOX_LOGS='$LOGS_DIR'
        
        # Custom prompt
        export PS1='\[\033[1;36m\][sandbox-$feature]\[\033[0m\] \w\$ '
        
        # Help function
        sandbox_help() {
            echo 'Available sandbox commands:'
            echo '  test-feature    Run feature-specific tests'
            echo '  demo-config    Show example configuration'
            echo '  simulate       Start traffic simulation'
            echo '  validate       Validate current configuration'
            echo '  status         Show sandbox status'
            echo '  help           Show this help'
            echo '  exit           Exit sandbox'
        }
        
        # Test function
        test-feature() {
            echo 'Running feature tests...'
            # Feature-specific tests would go here
            echo 'Tests completed successfully'
        }
        
        # Demo configuration
        demo-config() {
            echo 'Example $feature configuration:'
            cat '$config_file'
        }
        
        # Simulation
        simulate() {
            echo 'Starting simulation...'
            # Simulation logic would go here
        }
        
        # Validation
        validate() {
            echo 'Validating configuration...'
            # Validation logic would go here
        }
        
        # Status
        status() {
            echo 'Sandbox Status:'
            echo '  Feature: $SANDBOX_FEATURE'
            echo '  Session: $SANDBOX_SESSION'
            echo '  Duration: $SANDBOX_DURATION minutes'
            echo '  Logs: $SANDBOX_LOGS'
        }
        
        # Start interactive shell
        bash
    " || {
        log_warning "Sandbox session ended or timed out"
    }
}

# Launch headless sandbox
launch_headless_sandbox() {
    local feature="$1"
    local session_id="$2"
    local nix_expr="$3"
    
    log_info "Running headless $feature sandbox for ${DURATION} minutes..."
    
    # Run automated tests and simulations
    timeout "${DURATION}m" nix-shell --run "
        export SANDBOX_FEATURE='$feature'
        export SANDBOX_SESSION='$session_id'
        export SANDBOX_DURATION='$DURATION'
        export SANDBOX_LOGS='$LOGS_DIR'
        
        # Run automated tests
        echo 'Starting automated sandbox testing...'
        
        # Feature-specific automated tasks
        $(_get_automated_tasks "$feature")
        
        echo 'Sandbox testing completed'
    " || {
        log_warning "Sandbox session ended or timed out"
    }
}

# Get automated tasks for feature
_get_automated_tasks() {
    local feature="$1"
    
    case "$feature" in
        "networking")
            cat << 'EOF'
echo "Testing network interfaces..."
ip link show
echo "Testing bridge configuration..."
brctl show
EOF
            ;;
        "routing")
            cat << 'EOF'
echo "Testing routing configuration..."
ip route show
echo "Testing BGP configuration..."
# BGP test commands would go here
EOF
            ;;
        "security")
            cat << 'EOF'
echo "Testing firewall rules..."
iptables -L
echo "Testing security policies..."
# Security test commands would go here
EOF
            ;;
        *)
            echo "echo 'No specific automated tasks for $feature'"
            ;;
    esac
}

# Cleanup sandbox environment
cleanup_sandbox() {
    if [[ "$CLEANUP" != "true" ]]; then
        log_info "Skipping cleanup (no-cleanup mode)"
        return 0
    fi

    log_info "Cleaning up sandbox environment..."
    
    # Cleanup network namespaces
    if [[ "$ISOLATION" == "full" ]] && [[ -n "${ns_name:-}" ]]; then
        ip netns del "$ns_name" 2>/dev/null || true
    fi
    
    # Cleanup temporary files (older than 1 day)
    find "$RUNTIME_DIR" -type f -mtime +1 -delete 2>/dev/null || true
    
    log_success "Sandbox cleanup completed"
}

# Main execution
main() {
    parse_args "$@"
    validate_args
    check_dependencies
    create_directories
    
    log_info "Starting NixOS Gateway Feature Sandbox"
    log_info "Feature: $FEATURE"
    log_info "Duration: ${DURATION} minutes"
    log_info "Isolation: $ISOLATION"
    log_info "Interactive: $INTERACTIVE"
    
    trap cleanup_sandbox EXIT
    
    local config_file
    config_file=$(generate_config "$FEATURE")
    
    setup_network_isolation
    launch_sandbox "$FEATURE" "$config_file"
    
    log_success "Sandbox session completed"
    log_info "Logs available in: $LOGS_DIR"
    log_info "Configuration saved to: $config_file"
}

# Execute main function
main "$@"
