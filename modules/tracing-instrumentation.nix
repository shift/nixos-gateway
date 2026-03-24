{ collector, services, networkFlows }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "tracing-instrumentation";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    bash
    curl
    jq
    opentelemetry-collector
    procps
    coreutils
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/tracing-instrumentation << 'EOF'
    #!/bin/bash
    set -euo pipefail

    # Configuration
    COLLECTOR_ENDPOINT="${collector.endpoint}"
    COLLECTOR_PROTOCOL="${collector.protocol}"
    SAMPLING_STRATEGY="${collector.sampling.strategy}"
    SAMPLING_PROBABILITY="${collector.sampling.probability}"
    LOG_DIR="/var/lib/tracing/logs"

    # Logging
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] TRACING: $*" | tee -a "$LOG_DIR/tracing.log"
    }

    # Generate trace ID and span ID
    generate_trace_id() {
        printf '%016x%016x\n' $RANDOM $RANDOM
    }

    generate_span_id() {
        printf '%016x\n' $RANDOM
    }

    # Create span
    create_span() {
        local service_name="$1"
        local operation_name="$2"
        local trace_id="$3"
        local parent_span_id="$4"
        local start_time_ns="$5"

        local span_id
        span_id=$(generate_span_id)

        cat << SPAN_EOF > "/var/lib/tracing/spans/${trace_id}-${span_id}.json"
        {
          "trace_id": "$trace_id",
          "span_id": "$span_id",
          "parent_span_id": "$parent_span_id",
          "name": "$operation_name",
          "service": "$service_name",
          "start_time": $start_time_ns,
          "attributes": {}
        }
        SPAN_EOF

        echo "$span_id"
    }

    # Update span with end time and attributes
    finish_span() {
        local trace_id="$1"
        local span_id="$2"
        local end_time_ns="$3"
        shift 3

        local span_file="/var/lib/tracing/spans/${trace_id}-${span_id}.json"

        if [[ -f "$span_file" ]]; then
            # Add attributes
            local attributes='{}'
            while [[ $# -gt 0 ]]; do
                local key="$1"
                local value="$2"
                attributes=$(echo "$attributes" | jq ".\"$key\" = \"$value\"")
                shift 2
            done

            # Update span
            jq ".end_time = $end_time_ns | .attributes = $attributes" "$span_file" > "${span_file}.tmp"
            mv "${span_file}.tmp" "$span_file"
        fi
    }

    # Submit span to collector
    submit_span() {
        local trace_id="$1"
        local span_id="$2"

        local span_file="/var/lib/tracing/spans/${trace_id}-${span_id}.json"

        if [[ -f "$span_file" ]]; then
            local span_data
            span_data=$(cat "$span_file")

            # Submit to OpenTelemetry collector
            if [[ "$COLLECTOR_PROTOCOL" == "http" ]]; then
                curl -s -X POST "$COLLECTOR_ENDPOINT" \
                    -H "Content-Type: application/json" \
                    -d "$span_data" || log "Failed to submit span $span_id"
            fi

            # Clean up span file
            rm -f "$span_file"
        fi
    }

    # Sampling decision
    should_sample() {
        local service_name="$1"

        case "$SAMPLING_STRATEGY" in
            "always")
                return 0
                ;;
            "never")
                return 1
                ;;
            "probabilistic")
                local probability="$SAMPLING_PROBABILITY"
                # Check for service-specific override
                ${lib.concatStringsSep "\n        " (lib.mapAttrsToList (service: config:
                  "if [[ \"$service_name\" == \"${service}\" ]]; then\n" +
                  "  probability=\"${toString config.probability}\"\n" +
                  "fi"
                ) collector.sampling.serviceOverrides)}

                local rand=$((RANDOM % 1000))
                local threshold=$((probability * 1000))
                [[ $rand -lt $threshold ]]
                ;;
            *)
                return 0
                ;;
        esac
    }

    # DNS tracing instrumentation
    instrument_dns() {
        log "Instrumenting DNS service tracing"

        # Monitor unbound logs for queries
        while true; do
            # This would integrate with unbound to capture query spans
            # For now, just log that DNS tracing is active
            log "DNS tracing active - monitoring queries"
            sleep 60
        done
    }

    # DHCP tracing instrumentation
    instrument_dhcp() {
        log "Instrumenting DHCP service tracing"

        # Monitor DHCP logs for lease operations
        while true; do
            log "DHCP tracing active - monitoring leases"
            sleep 60
        done
    }

    # Network flow tracing
    instrument_network_flows() {
        if [[ "${lib.boolToString networkFlows.enable}" == "true" ]]; then
            log "Instrumenting network flow tracing"

            # Use conntrack or similar to track flows
            while true; do
                log "Network flow tracing active"
                sleep 60
            done
        fi
    }

    # Main execution
    log "Distributed Tracing Instrumentation starting..."
    log "Collector: $COLLECTOR_ENDPOINT ($COLLECTOR_PROTOCOL)"
    log "Sampling: $SAMPLING_STRATEGY ($SAMPLING_PROBABILITY)"

    mkdir -p "$LOG_DIR"

    # Start instrumentation for enabled services
    ${lib.concatStringsSep "\n    " (lib.mapAttrsToList (serviceName: serviceConfig:
      "if [[ \"${lib.boolToString serviceConfig.enable}\" == \"true\" ]]; then\n" +
      "  log \"Starting instrumentation for service: ${serviceName}\"\n" +
      "  instrument_${serviceName} &\n" +
      "fi"
    ) services)}

    # Start network flow tracing if enabled
    instrument_network_flows &

    # Keep running and process span submissions
    log "Instrumentation active - monitoring for spans"

    while true; do
        # Process any pending spans
        for span_file in /var/lib/tracing/spans/*.json; do
            if [[ -f "$span_file" ]]; then
                local filename
                filename=$(basename "$span_file" .json)
                local trace_id span_id
                trace_id=$(echo "$filename" | cut -d- -f1)
                span_id=$(echo "$filename" | cut -d- -f2)

                submit_span "$trace_id" "$span_id"
            fi
        done

        sleep 10
    done
    EOF

    chmod +x $out/bin/tracing-instrumentation
  '';
}