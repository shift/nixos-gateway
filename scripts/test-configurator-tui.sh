#!/usr/bin/env bash
# scripts/test-configurator-tui.sh

set -euo pipefail

# TUI Configuration
TITLE="NixOS Gateway Comprehensive Testing Configurator"
VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# UI Elements
draw_box() {
    local width="$1"
    local height="$2"
    local title="$3"

    # Top border
    echo -n "┌"
    printf '─%.0s' $(seq 1 $((width - 2)))
    echo "┐"

    # Title
    if [[ -n "$title" ]]; then
        printf "│ %-*s │\n" $((width - 4)) "$title"
        echo -n "├"
        printf '─%.0s' $(seq 1 $((width - 2)))
        echo "┤"
    fi

    # Content area
    for ((i = 0; i < height; i++)); do
        echo -n "│"
        printf ' %-*s ' $((width - 4)) ""
        echo "│"
    done

    # Bottom border
    echo -n "└"
    printf '─%.0s' $(seq 1 $((width - 2)))
    echo "┘"
}

show_header() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
███╗   ██╗██╗██╗  ██╗ ██████╗ ███████╗
████╗  ██║██║╚██╗██╔╝██╔═══██╗██╔════╝
██╔██╗ ██║██║ ╚███╔╝ ██║   ██║███████╗
██║╚██╗██║██║ ██╔██╗ ██║   ██║╚════██║
██║ ╚████║██║██╔╝ ██╗╚██████╔╝███████║
╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝

    Gateway Comprehensive Testing Suite
EOF
    echo -e "${NC}"
    echo -e "${YELLOW}Version ${VERSION} - $(date)${NC}"
    echo
}

select_option() {
    local prompt="$1"
    shift
    local options=("$@")
    local selected=0

    while true; do
        echo -e "${CYAN}$prompt${NC}"
        for i in "${!options[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "${GREEN}  ▸ ${options[$i]}${NC}"
            else
                echo -e "    ${options[$i]}"
            fi
        done

        read -rsn1 key
        case "$key" in
            "A") # Up arrow
                ((selected--))
                if [[ $selected -lt 0 ]]; then
                    selected=$((${#options[@]} - 1))
                fi
                ;;
            "B") # Down arrow
                ((selected++))
                if [[ $selected -ge ${#options[@]} ]]; then
                    selected=0
                fi
                ;;
            "") # Enter
                echo
                return $selected
                ;;
        esac

        # Move cursor back up
        for ((i = 0; i < ${#options[@]}; i++)); do
            echo -ne "\033[1A\033[2K"
        done
    done
}

input_text() {
    local prompt="$1"
    local default="$2"
    local value=""

    echo -ne "${CYAN}$prompt${NC} "
    if [[ -n "$default" ]]; then
        echo -ne "${YELLOW}[$default]${NC} "
    fi

    read -r value
    if [[ -z "$value" && -n "$default" ]]; then
        value="$default"
    fi

    echo "$value"
}

confirm_action() {
    local prompt="$1"
    local default="${2:-n}"

    echo -ne "${CYAN}$prompt${NC} "
    if [[ "$default" == "y" ]]; then
        echo -ne "${YELLOW}[Y/n]${NC} "
    else
        echo -ne "${YELLOW}[y/N]${NC} "
    fi

    read -r response
    case "${response:-$default}" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Main configuration collection
main() {
    show_header

    echo -e "${WHITE}Welcome to the NixOS Gateway Comprehensive Testing Configurator${NC}"
    echo -e "${WHITE}This tool will guide you through configuring your test run.${NC}"
    echo

    # Test Scope Selection
    echo -e "${BLUE}Step 1: Select Test Scope${NC}"
    local scopes=(
        "core - Basic networking, DNS, DHCP, and security"
        "networking - All networking-related features"
        "security - Security features and firewall"
        "monitoring - Monitoring and observability"
        "vpn - VPN and routing features"
        "advanced - Advanced features (API, service mesh, etc.)"
        "full - Complete test suite (all features)"
        "feature - Specific feature (will prompt for selection)"
    )

    select_option "Choose the test scope:" "${scopes[@]}"
    local scope_index=$?
    local scope=$(echo "${scopes[$scope_index]}" | cut -d' ' -f1)

    # Feature selection if scope is "feature"
    local feature="all"
    if [[ "$scope" == "feature" ]]; then
        echo
        echo -e "${BLUE}Step 1b: Select Specific Feature${NC}"
        local features=(
            "dns - DNS server and resolver"
            "dhcp - DHCP server functionality"
            "firewall - Firewall and security policies"
            "monitoring - Metrics and health monitoring"
            "vpn - VPN server and client"
            "routing - BGP and OSPF routing"
            "load-balancing - Load balancing and HA"
            "api - API gateway functionality"
            "backup - Backup and recovery"
            "all - All features (same as full scope)"
        )

        select_option "Choose the specific feature:" "${features[@]}"
        local feature_index=$?
        feature=$(echo "${features[$feature_index]}" | cut -d' ' -f1)
    fi

    echo

    # Output Configuration
    echo -e "${BLUE}Step 2: Output Configuration${NC}"
    local output_dir=$(input_text "Output directory for test results:" "test-results/$(date +%Y%m%d-%H%M%S)")
    local parallel_execution=true

    if confirm_action "Run tests in parallel for faster execution?" "y"; then
        parallel_execution=true
    else
        parallel_execution=false
    fi

    local verbose_logging=false
    if confirm_action "Enable verbose logging?" "n"; then
        verbose_logging=true
    fi

    echo

    # Resource Configuration
    echo -e "${BLUE}Step 3: Resource Configuration${NC}"
    local memory_limit=$(input_text "Memory limit per test (GB):" "2")
    local cpu_limit=$(input_text "CPU cores per test:" "2")
    local time_limit=$(input_text "Time limit per test (minutes):" "30")

    echo

    # Test Environment
    echo -e "${BLUE}Step 4: Test Environment${NC}"
    local environments=(
        "isolated - No external network access"
        "internet - Full internet access for external tests"
        "enterprise - Multi-segment enterprise simulation"
    )

    select_option "Choose test environment:" "${environments[@]}"
    local env_index=$?
    local environment=$(echo "${environments[$env_index]}" | cut -d' ' -f1)

    echo

    # Advanced Options
    echo -e "${BLUE}Step 5: Advanced Options${NC}"
    local collect_evidence=true
    if ! confirm_action "Collect test evidence (logs, metrics, outputs)?" "y"; then
        collect_evidence=false
    fi

    local generate_reports=true
    if ! confirm_action "Generate detailed test reports?" "y"; then
        generate_reports=false
    fi

    local cleanup_after=true
    if ! confirm_action "Clean up test environment after completion?" "y"; then
        cleanup_after=false
    fi

    echo

    # Configuration Summary
    echo -e "${BLUE}Configuration Summary${NC}"
    echo -e "${WHITE}Scope:${NC} $scope"
    echo -e "${WHITE}Feature:${NC} $feature"
    echo -e "${WHITE}Output Directory:${NC} $output_dir"
    echo -e "${WHITE}Parallel Execution:${NC} $parallel_execution"
    echo -e "${WHITE}Verbose Logging:${NC} $verbose_logging"
    echo -e "${WHITE}Memory Limit:${NC} ${memory_limit}GB"
    echo -e "${WHITE}CPU Limit:${NC} ${cpu_limit} cores"
    echo -e "${WHITE}Time Limit:${NC} ${time_limit} minutes"
    echo -e "${WHITE}Environment:${NC} $environment"
    echo -e "${WHITE}Collect Evidence:${NC} $collect_evidence"
    echo -e "${WHITE}Generate Reports:${NC} $generate_reports"
    echo -e "${WHITE}Cleanup After:${NC} $cleanup_after"
    echo

    # Final Confirmation
    if confirm_action "Start testing with this configuration?" "y"; then
        echo
        echo -e "${GREEN}Starting comprehensive testing...${NC}"
        echo

        # Export configuration for the main script
        export TEST_SCOPE="$scope"
        export TEST_FEATURE="$feature"
        export TEST_OUTPUT_DIR="$output_dir"
        export TEST_PARALLEL="$parallel_execution"
        export TEST_VERBOSE="$verbose_logging"
        export TEST_MEMORY_LIMIT="$memory_limit"
        export TEST_CPU_LIMIT="$cpu_limit"
        export TEST_TIME_LIMIT="$time_limit"
        export TEST_ENVIRONMENT="$environment"
        export TEST_COLLECT_EVIDENCE="$collect_evidence"
        export TEST_GENERATE_REPORTS="$generate_reports"
        export TEST_CLEANUP="$cleanup_after"

        # Run the main testing script
        ./run-comprehensive-testing.sh

    else
        echo
        echo -e "${YELLOW}Testing cancelled. Run this configurator again to start over.${NC}"
        exit 0
    fi
}

# Run main function
main "$@"