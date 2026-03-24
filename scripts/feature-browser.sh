#!/usr/bin/env bash
set -euo pipefail

# Feature Discovery & Browser Tool
# Interactive exploration of NixOS Gateway features with live demonstrations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Feature catalog
declare -A FEATURE_CATEGORIES=(
    ["Networking"]="networking routing interfaces bridges"
    ["Security"]="security firewall zero-trust microsegmentation"
    ["Performance"]="performance xdp ebpf qos acceleration"
    ["Services"]="dns dhcp vpn monitoring"
    ["Advanced"]="policy automation orchestration clustering"
)

declare -A FEATURE_DESCRIPTIONS=(
    ["networking"]="Core networking features including interfaces, bridges, and VLANs"
    ["routing"]="Advanced routing protocols (BGP, OSPF) and policy routing"
    ["security"]="Firewall, zero-trust, microsegmentation, and threat protection"
    ["performance"]="XDP/eBPF acceleration, QoS, and traffic shaping"
    ["dns"]="DNS resolution, forwarding, caching, and security"
    ["dhcp"]="DHCP server, relay, and lease management"
    ["vpn"]="WireGuard, Tailscale, and site-to-site VPN connectivity"
    ["monitoring"]="Metrics, logging, tracing, and health monitoring"
    ["interfaces"]="Network interface management and configuration"
    ["bridges"]="Layer 2 network bridges and switching"
    ["firewall"]="iptables/nftables firewall management"
    ["zero-trust"]="Zero-trust network access and microsegmentation"
    ["xdp"]="XDP (eXpress Data Path) acceleration for high-performance networking"
    ["ebpf"]="eBPF programmable networking and security"
    ["qos"]="Quality of Service and traffic shaping"
    ["policy"]="Policy-based routing and network policies"
    ["automation"]="Network automation and configuration management"
    ["orchestration"]="Service orchestration and container networking"
    ["clustering"]="High availability clustering and load balancing"
)

declare -A FEATURE_EXAMPLES=(
    ["networking"]="Basic network interface configuration with DHCP"
    ["routing"]="BGP routing with route maps and policy control"
    ["security"]="Zero-trust microsegmentation with granular policies"
    ["performance"]="XDP-based packet filtering at line rate"
    ["dns"]="Secure DNS with DNSSEC and caching resolver"
    ["dhcp"]="Enterprise DHCP with option handling and failover"
    ["vpn"]="WireGuard site-to-site VPN with dynamic routing"
    ["monitoring"]="Prometheus metrics with Grafana dashboards"
    ["interfaces"]="Bonded interfaces with failover and LACP"
    ["bridges"]="VLAN-aware bridge with STP support"
    ["firewall"]="Stateful firewall with application layer filtering"
    ["zero-trust"]="Identity-based access control and segmentation"
    ["xdp"]="High-performance DDoS mitigation with XDP"
    ["ebpf"]="Custom eBPF programs for network monitoring"
    ["qos"]="Per-application bandwidth allocation"
    ["policy"]="SD-WAN traffic engineering with policy routing"
    ["automation"]="Infrastructure as Code with NixOS"
    ["orchestration"]="Kubernetes networking integration"
    ["clustering"]="Active-passive firewall clustering"
)

# Help function
show_help() {
    cat << EOF
${BOLD}NixOS Gateway Feature Discovery Browser${NC}

${BOLD}USAGE:${NC}
    $0 [OPTIONS]

${BOLD}OPTIONS:${NC}
    -c, --category <CATEGORY>    Filter by category
    -f, --feature <FEATURE>      Focus on specific feature
    -i, --interactive            Interactive mode (default)
    -d, --demonstrate            Show live demonstrations
    -l, --list                   List available features
    -s, --search <TERM>          Search features
    -v, --verbose                Verbose output
    -h, --help                   Show this help

${BOLD}CATEGORIES:${NC}
    Networking    Core networking and routing features
    Security      Firewall and zero-trust security
    Performance   Acceleration and optimization
    Services      DNS, DHCP, VPN, monitoring
    Advanced      Automation, orchestration, clustering

${BOLD}EXAMPLES:${NC}
    $0                           # Interactive browser
    $0 --category Networking     # Browse networking features
    $0 --feature xdp             # Focus on XDP acceleration
    $0 --search routing          # Search routing features
    $0 --demonstrate             # Show live demonstrations

EOF
}

# Default values
CATEGORY=""
FEATURE=""
INTERACTIVE=true
DEMONSTRATE=false
LIST_ONLY=false
SEARCH=""

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--category)
                CATEGORY="$2"
                shift 2
                ;;
            -f|--feature)
                FEATURE="$2"
                shift 2
                ;;
            -i|--interactive)
                INTERACTIVE=true
                shift
                ;;
            -d|--demonstrate)
                DEMONSTRATE=true
                shift
                ;;
            -l|--list)
                LIST_ONLY=true
                shift
                ;;
            -s|--search)
                SEARCH="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Display functions
display_header() {
    clear
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                 NIXOS GATEWAY FEATURE BROWSER               ║
║                    Interactive Discovery Tool                ║
╚══════════════════════════════════════════════════════════════╝
EOF
}

display_menu() {
    cat << EOF
${BOLD}Main Menu:${NC}

1) ${CYAN}Browse by Category${NC}
2) ${YELLOW}Search Features${NC}
3) ${GREEN}Feature Details${NC}
4) ${PURPLE}Live Demonstrations${NC}
5) ${BLUE}Configuration Examples${NC}
6) ${RED}Performance Metrics${NC}
7) Help & Documentation
0) Exit

${BOLD}Current Selection:${NC} $([ -n "$CATEGORY" ] && echo "Category: $CATEGORY" || echo "All Categories")

${BOLD}Enter choice:${NC} "
}

# Display features by category
display_category_features() {
    local category="$1"
    
    echo -e "\n${BOLD}${category} Features:${NC}"
    echo "─────────────────────────────────────────────────────"
    
    local features="${FEATURE_CATEGORIES[$category]}"
    local feature_array=($features)
    
    for i in "${!feature_array[@]}"; do
        local feature="${feature_array[$i]}"
        local description="${FEATURE_DESCRIPTIONS[$feature]}"
        
        printf "%2d) ${CYAN}%-20s${NC} %s\n" $((i+1)) "$feature" "$description"
    done
    
    echo ""
    echo "${YELLOW}Enter feature number for details, or 'b' to go back:${NC} "
}

# Display feature details
display_feature_details() {
    local feature="$1"
    
    display_header
    
    echo -e "\n${BOLD}Feature Details: ${CYAN}$feature${NC}"
    echo "==============================================="
    
    echo -e "\n${BOLD}Description:${NC}"
    echo "${FEATURE_DESCRIPTIONS[$feature]}"
    
    echo -e "\n${BOLD}Example Use Case:${NC}"
    echo "${FEATURE_EXAMPLES[$feature]}"
    
    echo -e "\n${BOLD}Configuration Example:${NC}"
    echo "${BLUE}$(get_feature_config "$feature")${NC}"
    
    echo -e "\n${BOLD}Available Actions:${NC}"
    echo "1) ${GREEN}Launch Sandbox${NC}    - Test in isolated environment"
    echo "2) ${YELLOW}View Documentation${NC} - In-depth technical details"
    echo "3) ${PURPLE}Live Demo${NC}          - See feature in action"
    echo "4) ${BLUE}Configuration Helper${NC} - Build your own config"
    echo "5) ${RED}Performance Test${NC}      - Benchmark feature"
    
    echo -e "\n${BOLD}Enter action number, or 'b' to go back:${NC} "
}

# Get feature configuration example
get_feature_config() {
    local feature="$1"
    
    case "$feature" in
        "networking")
            cat << 'EOF'
networking = {
  interfaces.eth0 = {
    ipv4.addresses = [ {
      address = "192.168.1.10";
      prefixLength = 24;
    } ];
  };
  
  bridges.br0 = {
    interfaces = [ "eth0" "eth1" ];
  };
}
EOF
            ;;
        "routing")
            cat << 'EOF'
services.bird2 = {
  enable = true;
  config = ''
    router id 192.168.1.1;
    protocol bgp {
      import all;
      export all;
      local 65001 as;
      neighbor 192.168.1.2 as 65002;
    };
  '';
};
EOF
            ;;
        "security")
            cat << 'EOF'
networking.firewall = {
  enable = true;
  zones.trusted.interfaces = [ "eth0" ];
  zones.dmz.interfaces = [ "eth1" ];
  
  rules.allow-web = {
    from = "dmz";
    to = [ "trusted" ];
    allowedPorts = [ 80 443 ];
  };
};
EOF
            ;;
        "performance")
            cat << 'EOF'
networking.xdp = {
  enable = true;
  programs = [{
    name = "ddos-mitigation";
    program = ./xdp-ddos-filter.o;
    interface = "eth0";
  }];
};

boot.kernel.sysctl = {
  "net.core.rmem_max" = 134217728;
  "net.core.wmem_max" = 134217728;
};
EOF
            ;;
        *)
            echo "# Configuration example for $feature"
            echo "# See documentation for detailed examples"
            ;;
    esac
}

# Search features
search_features() {
    local term="$1"
    
    echo -e "\n${BOLD}Search Results for '${YELLOW}$term${NC}':${NC}"
    echo "=========================================="
    
    local found=false
    
    for feature in "${!FEATURE_DESCRIPTIONS[@]}"; do
        local description="${FEATURE_DESCRIPTIONS[$feature]}"
        local example="${FEATURE_EXAMPLES[$feature]}"
        
        if [[ "$feature" =~ $term ]] || [[ "$description" =~ $term ]] || [[ "$example" =~ $term ]]; then
            echo -e "\n${CYAN}$feature${NC}"
            echo "  $description"
            echo "  ${YELLOW}Example:${NC} $example"
            found=true
        fi
    done
    
    if [[ "$found" != "true" ]]; then
        echo -e "${RED}No features found matching '$term'${NC}"
    fi
    
    echo ""
    echo "${YELLOW}Press Enter to continue:${NC} "
}

# Display live demonstrations
display_demonstrations() {
    echo -e "\n${BOLD}Live Feature Demonstrations:${NC}"
    echo "================================"
    
    cat << 'EOF'
1) 🌐 Networking Demo
   • Interface configuration
   • Bridge setup and STP
   • VLAN segmentation

2) 🔐 Security Demo
   • Firewall rule testing
   • Zero-trust policies
   • Threat simulation

3) ⚡ Performance Demo
   • XDP packet filtering
   • eBPF monitoring
   • QoS traffic shaping

4) 🛠️ Services Demo
   • DNS resolution testing
   • DHCP lease management
   • VPN connectivity

5) 📊 Monitoring Demo
   • Real-time metrics
   • Alerting configuration
   • Log aggregation

Select demo number to launch, or 'b' to go back: 
EOF
}

# Launch demonstration
launch_demonstration() {
    local demo_num="$1"
    
    case "$demo_num" in
        "1")
            echo -e "\n${GREEN}Launching Networking Demo...${NC}"
            "$SCRIPT_DIR/sandbox-launch.sh" --feature networking --duration 10 --interactive true
            ;;
        "2")
            echo -e "\n${GREEN}Launching Security Demo...${NC}"
            "$SCRIPT_DIR/sandbox-launch.sh" --feature security --duration 10 --interactive true
            ;;
        "3")
            echo -e "\n${GREEN}Launching Performance Demo...${NC}"
            "$SCRIPT_DIR/sandbox-launch.sh" --feature performance --duration 10 --interactive true
            ;;
        "4")
            echo -e "\n${GREEN}Launching Services Demo...${NC}"
            "$SCRIPT_DIR/sandbox-launch.sh" --feature dns --duration 10 --interactive true
            ;;
        "5")
            echo -e "\n${GREEN}Launching Monitoring Demo...${NC}"
            "$SCRIPT_DIR/sandbox-launch.sh" --feature monitoring --duration 10 --interactive true
            ;;
        *)
            echo -e "${RED}Invalid demo selection${NC}"
            ;;
    esac
}

# Interactive mode
interactive_mode() {
    while true; do
        display_header
        display_menu
        
        read -r choice
        
        case "$choice" in
            "1")
                # Browse by category
                echo ""
                echo "${BOLD}Available Categories:${NC}"
                echo "========================"
                local i=1
                for category in "${!FEATURE_CATEGORIES[@]}"; do
                    echo "$i) $category"
                    ((i++))
                done
                
                echo ""
                echo "${YELLOW}Select category number:${NC} "
                read -r cat_choice
                
                # Parse category selection
                local categories_array=("${!FEATURE_CATEGORIES[@]}")
                if [[ "$cat_choice" =~ ^[0-9]+$ ]] && [[ "$cat_choice" -ge 1 ]] && [[ "$cat_choice" -le "${#categories_array[@]}" ]]; then
                    local selected_category="${categories_array[$((cat_choice-1))]}"
                    display_category_features "$selected_category"
                    read -r feature_choice
                    
                    # Handle feature selection
                    local features_array=(${FEATURE_CATEGORIES[$selected_category]})
                    if [[ "$feature_choice" =~ ^[0-9]+$ ]] && [[ "$feature_choice" -ge 1 ]] && [[ "$feature_choice" -le "${#features_array[@]}" ]]; then
                        local selected_feature="${features_array[$((feature_choice-1))]}"
                        display_feature_details "$selected_feature"
                        read -r action_choice
                        
                        # Handle action selection
                        case "$action_choice" in
                            "1")
                                echo -e "${GREEN}Launching sandbox for $selected_feature...${NC}"
                                "$SCRIPT_DIR/sandbox-launch.sh" --feature "$selected_feature" --duration 15 --interactive true
                                ;;
                            "3")
                                echo -e "${GREEN}Launching live demo for $selected_feature...${NC}"
                                "$SCRIPT_DIR/sandbox-launch.sh" --feature "$selected_feature" --duration 10 --interactive true
                                ;;
                        esac
                    fi
                fi
                ;;
            "2")
                # Search features
                echo ""
                echo "${YELLOW}Enter search term:${NC} "
                read -r search_term
                search_features "$search_term"
                read -r _
                ;;
            "3")
                # Feature details
                echo ""
                echo "${YELLOW}Enter feature name:${NC} "
                read -r feature_name
                if [[ -v "FEATURE_DESCRIPTIONS[$feature_name]" ]]; then
                    display_feature_details "$feature_name"
                    read -r _
                else
                    echo -e "${RED}Feature '$feature_name' not found${NC}"
                fi
                ;;
            "4")
                # Live demonstrations
                display_demonstrations
                read -r demo_choice
                if [[ "$demo_choice" =~ ^[1-5]$ ]]; then
                    launch_demonstration "$demo_choice"
                fi
                ;;
            "0"|"q"|"quit"|"exit")
                echo -e "\n${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please try again.${NC}"
                sleep 1
                ;;
        esac
    done
}

# List mode
list_features() {
    echo -e "${BOLD}Available NixOS Gateway Features:${NC}"
    echo "====================================="
    
    if [[ -n "$CATEGORY" ]]; then
        local features="${FEATURE_CATEGORIES[$CATEGORY]}"
        echo -e "\n${CYAN}$CATEGORY:${NC}"
        for feature in $features; do
            echo "  • $feature - ${FEATURE_DESCRIPTIONS[$feature]}"
        done
    elif [[ -n "$SEARCH" ]]; then
        search_features "$SEARCH"
    else
        for category in "${!FEATURE_CATEGORIES[@]}"; do
            echo -e "\n${CYAN}$category:${NC}"
            local features="${FEATURE_CATEGORIES[$category]}"
            for feature in $features; do
                echo "  • $feature - ${FEATURE_DESCRIPTIONS[$feature]}"
            done
        done
    fi
    
    echo ""
}

# Demonstration mode
demonstration_mode() {
    if [[ -n "$FEATURE" ]]; then
        echo -e "${GREEN}Demonstrating $FEATURE...${NC}"
        "$SCRIPT_DIR/sandbox-launch.sh" --feature "$FEATURE" --duration 20 --interactive true
    else
        display_demonstrations
        read -r demo_choice
        if [[ "$demo_choice" =~ ^[1-5]$ ]]; then
            launch_demonstration "$demo_choice"
        fi
    fi
}

# Main execution
main() {
    parse_args "$@"
    
    # Validate arguments
    if [[ -n "$CATEGORY" ]] && [[ ! -v "FEATURE_CATEGORIES[$CATEGORY]" ]]; then
        echo -e "${RED}Unknown category: $CATEGORY${NC}"
        echo "Available categories: ${!FEATURE_CATEGORIES[*]}"
        exit 1
    fi
    
    if [[ -n "$FEATURE" ]] && [[ ! -v "FEATURE_DESCRIPTIONS[$FEATURE]" ]]; then
        echo -e "${RED}Unknown feature: $FEATURE${NC}"
        echo "Use --list to see available features"
        exit 1
    fi
    
    # Execute based on mode
    if [[ "$LIST_ONLY" == "true" ]]; then
        list_features
    elif [[ "$DEMONSTRATE" == "true" ]]; then
        demonstration_mode
    elif [[ "$INTERACTIVE" == "true" ]]; then
        interactive_mode
    else
        list_features
    fi
}

# Execute main function
main "$@"
