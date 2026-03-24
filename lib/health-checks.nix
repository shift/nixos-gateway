{ lib }:

let
  inherit (lib)
    mkOption
    types
    optionalAttrs
    mapAttrsToList
    concatStringsSep
    filter
    mapAttrs
    mapAttrs'
    ;

  # Health check type definitions
  healthCheckTypes = {
    # Network checks
    interface = {
      description = "Network interface health check";
      requiredFields = [ "interface" ];
      optionalFields = [
        "checkType"
        "expectedState"
        "linkQuality"
        "congestion"
        "timeout"
      ];
    };

    routing = {
      description = "Routing table health check";
      requiredFields = [ "route" ];
      optionalFields = [
        "checkType"
        "gateway"
        "metric"
        "table"
        "timeout"
      ];
    };

    connectivity = {
      description = "Network connectivity health check";
      requiredFields = [ "target" ];
      optionalFields = [
        "protocol"
        "port"
        "timeout"
        "retries"
        "expectedLatency"
      ];
    };

    # DNS checks
    query = {
      description = "DNS query health check";
      requiredFields = [
        "target"
        "query"
      ];
      optionalFields = [
        "expectedResult"
        "recordType"
        "timeout"
        "retries"
        "cacheCheck"
      ];
    };

    zone = {
      description = "DNS zone integrity health check";
      requiredFields = [ "zone" ];
      optionalFields = [
        "serialCheck"
        "soaCheck"
        "transferCheck"
        "timeout"
      ];
    };

    resolver = {
      description = "DNS resolver performance check";
      requiredFields = [ "queries" ];
      optionalFields = [
        "latencyThreshold"
        "successRateThreshold"
        "cacheHitRateThreshold"
        "timeout"
      ];
    };

    # DHCP checks
    dhcp-server = {
      description = "DHCP server health check";
      requiredFields = [ "interface" ];
      optionalFields = [
        "leaseCheck"
        "poolUtilization"
        "responseTime"
        "timeout"
      ];
    };

    dhcp-database = {
      description = "DHCP database integrity check";
      requiredFields = [ "path" ];
      optionalFields = [
        "checkType"
        "leaseCount"
        "conflictCheck"
        "timeout"
      ];
    };

    # Security checks
    ids = {
      description = "Intrusion Detection System health check";
      requiredFields = [ "process" ];
      optionalFields = [
        "rulesLoaded"
        "packetRate"
        "dropRate"
        "alertRate"
        "timeout"
      ];
    };

    firewall = {
      description = "Firewall rules health check";
      requiredFields = [ "table" ];
      optionalFields = [
        "chain"
        "ruleCount"
        "policyCheck"
        "timeout"
      ];
    };

    # System checks
    process = {
      description = "Process health check";
      requiredFields = [ "name" ];
      optionalFields = [
        "user"
        "memoryLimit"
        "cpuLimit"
        "restartCount"
        "timeout"
      ];
    };

    filesystem = {
      description = "Filesystem health check";
      requiredFields = [ "path" ];
      optionalFields = [
        "checkType"
        "minFreeSpace"
        "permissions"
        "inodeCheck"
        "timeout"
      ];
    };

    system = {
      description = "System resource health check";
      requiredFields = [ "resource" ];
      optionalFields = [
        "threshold"
        "warning"
        "critical"
        "timeout"
      ];
    };

    # Database checks
    database = {
      description = "Database integrity health check";
      requiredFields = [ "path" ];
      optionalFields = [
        "checkType"
        "tableCheck"
        "connectionCheck"
        "timeout"
      ];
    };

    # Generic checks
    port = {
      description = "Port connectivity health check";
      requiredFields = [ "port" ];
      optionalFields = [
        "protocol"
        "host"
        "timeout"
        "retries"
      ];
    };

    script = {
      description = "Custom script health check";
      requiredFields = [ "path" ];
      optionalFields = [
        "timeout"
        "args"
        "expectedExitCode"
      ];
    };

    http = {
      description = "HTTP endpoint health check";
      requiredFields = [ "url" ];
      optionalFields = [
        "method"
        "expectedStatus"
        "expectedContent"
        "timeout"
        "headers"
      ];
    };

    metric = {
      description = "Metric-based health check";
      requiredFields = [ "metric" ];
      optionalFields = [
        "threshold"
        "operator"
        "window"
        "source"
      ];
    };
  };

  # Validate health check configuration
  validateHealthCheck =
    check:
    let
      checkType = check.type or (throw "Health check missing 'type' field");
      typeDef = healthCheckTypes.${checkType} or (throw "Unknown health check type: ${checkType}");

      missingRequired = filter (
        field: !(check ? ${field}) || check.${field} == null
      ) typeDef.requiredFields;
      hasAllRequired = missingRequired == [ ];
    in
    assert lib.assertMsg hasAllRequired
      "Health check type '${checkType}' missing required fields: ${concatStringsSep ", " missingRequired}";
    check;

  # Validate health check configuration for a service
  validateServiceHealthChecks =
    serviceName: checks:
    let
      validatedChecks = map validateHealthCheck checks;
      hasValidInterval =
        if checks ? interval && checks.interval != null then
          (builtins.isString checks.interval && builtins.match "^[0-9]+[smh]$" checks.interval != null)
        else
          true;
      hasValidTimeout =
        if checks ? timeout && checks.timeout != null then
          (builtins.isString checks.timeout && builtins.match "^[0-9]+[smh]$" checks.timeout != null)
        else
          true;
    in
    assert lib.assertMsg hasValidInterval
      "Service '${serviceName}' has invalid interval format: ${toString (checks.interval or "null")}";
    assert lib.assertMsg hasValidTimeout
      "Service '${serviceName}' has invalid timeout format: ${toString (checks.timeout or "null")}";
    checks // { checks = validatedChecks; };

  # Generate health check script for individual check
  generateHealthCheckScript =
    check:
    let
      timeout = if (check.timeout or null) != null then check.timeout else "5s";
      retries = if (check.retries or null) != null then check.retries else 3;
    in
    if check.type == "interface" then
      ''
        # Network interface health check
        expected_state=${check.expectedState or "UP"}
        check_type=${check.checkType or "basic"}

        echo "Checking interface ${check.interface} (type: $check_type)"

        # Basic interface check
        if ! ip link show ${check.interface} >/dev/null 2>&1; then
          echo "Interface ${check.interface} does not exist"
          exit 1
        fi

        # State check
        if ! ip link show ${check.interface} | grep -q "state $expected_state"; then
          echo "Interface ${check.interface} not in expected state $expected_state"
          exit 1
        fi

        # Link quality check (if requested)
        ${if check.linkQuality or false then ''
          # Check carrier status
          if ! cat /sys/class/net/${check.interface}/carrier 2>/dev/null | grep -q "1"; then
            echo "Interface ${check.interface} has no carrier"
            exit 1
          fi
        '' else ""}

        # Congestion check (if requested)
        ${if check.congestion or false then ''
          # Check for interface congestion (high tx queue length)
          tx_queue=$(cat /sys/class/net/${check.interface}/tx_queue_len 2>/dev/null || echo "0")
          if [ "$tx_queue" -gt 1000 ]; then
            echo "Interface ${check.interface} shows congestion (tx_queue_len: $tx_queue)"
            exit 1
          fi
        '' else ""}

        echo "Interface ${check.interface} check passed"
      ''
    else if check.type == "routing" then
      ''
        # Routing table health check
        check_type=${check.checkType or "basic"}
        table=${check.table or "main"}

        echo "Checking routing for ${check.route} in table $table"

        # Check if route exists
        if ! ip route show table $table ${check.route} >/dev/null 2>&1; then
          echo "Route ${check.route} not found in table $table"
          exit 1
        fi

        # Gateway check (if specified)
        ${if check.gateway or null != null then ''
          if ! ip route show table $table ${check.route} | grep -q "via ${check.gateway}"; then
            echo "Route ${check.route} does not use expected gateway ${check.gateway}"
            exit 1
          fi
        '' else ""}

        # Metric check (if specified)
        ${if check.metric or null != null then ''
          if ! ip route show table $table ${check.route} | grep -q "metric ${toString check.metric}"; then
            echo "Route ${check.route} does not have expected metric ${toString check.metric}"
            exit 1
          fi
        '' else ""}

        echo "Routing check for ${check.route} passed"
      ''
    else if check.type == "connectivity" then
      ''
        # Network connectivity health check
        protocol=${check.protocol or "tcp"}
        port=${toString (check.port or 80)}
        target=${check.target}

        echo "Checking connectivity to $target:$port ($protocol)"

        if [ "$protocol" = "tcp" ]; then
          timeout ${timeout} nc -zv "$target" "$port" >/dev/null 2>&1
        elif [ "$protocol" = "udp" ]; then
          timeout ${timeout} nc -zuv "$target" "$port" >/dev/null 2>&1
        elif [ "$protocol" = "icmp" ]; then
          timeout ${timeout} ping -c 1 -W 1 "$target" >/dev/null 2>&1
        else
          echo "Unsupported protocol: $protocol"
          exit 1
        fi

        # Latency check (if specified)
        ${if check.expectedLatency or null != null then ''
          start_time=$(date +%s%N)
          if [ "$protocol" = "icmp" ]; then
            ping -c 1 -W 1 "$target" >/dev/null 2>&1
          else
            nc -zv "$target" "$port" >/dev/null 2>&1
          fi
          end_time=$(date +%s%N)
          latency=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds

          if [ $latency -gt ${toString check.expectedLatency} ]; then
            echo "Latency $latency ms exceeds threshold ${toString check.expectedLatency} ms"
            exit 1
          fi
        '' else ""}
      ''
    else if check.type == "query" then
      ''
        # DNS query health check
        record_type=${check.recordType or "A"}
        cache_check=${if check.cacheCheck or false then "true" else "false"}

        echo "DNS query check: ${check.query} ($record_type) @${check.target}"

        # Perform DNS query
        result=$(timeout ${timeout} dig @${check.target} ${check.query} $record_type +short 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$result" ]; then
          echo "DNS query failed for ${check.query}"
          exit 1
        fi

        # Expected result check (if specified)
        ${if check.expectedResult or null != null then ''
          if ! echo "$result" | grep -q "${check.expectedResult}"; then
            echo "DNS query result does not match expected: ${check.expectedResult}"
            echo "Got: $result"
            exit 1
          fi
        '' else ""}

        echo "DNS query check passed"
      ''
    else if check.type == "zone" then
      ''
        # DNS zone integrity health check
        echo "Checking DNS zone integrity for ${check.zone}"

        # SOA check
        ${if check.soaCheck or true then ''
          if ! timeout ${timeout} dig @localhost ${check.zone} SOA +short >/dev/null 2>&1; then
            echo "SOA check failed for zone ${check.zone}"
            exit 1
          fi
        '' else ""}

        # Serial check (ensure serial is increasing)
        ${if check.serialCheck or false then ''
          current_serial=$(dig @localhost ${check.zone} SOA +short | awk '{print $3}' 2>/dev/null)
          if [ -f "/run/gateway-health/zone_${check.zone}_last_serial" ]; then
            last_serial=$(cat "/run/gateway-health/zone_${check.zone}_last_serial")
            if [ "$current_serial" -lt "$last_serial" ]; then
              echo "Zone serial decreased: $last_serial -> $current_serial"
              exit 1
            fi
          fi
          echo "$current_serial" > "/run/gateway-health/zone_${check.zone}_last_serial"
        '' else ""}

        # Zone transfer check (if enabled)
        ${if check.transferCheck or false then ''
          if ! timeout ${timeout} dig @localhost ${check.zone} AXFR | grep -q "${check.zone}"; then
            echo "Zone transfer check failed for ${check.zone}"
            exit 1
          fi
        '' else ""}

        echo "Zone integrity check passed for ${check.zone}"
      ''
    else if check.type == "resolver" then
      ''
        # DNS resolver performance check
        queries=${check.queries or ["example.com"]}
        latency_threshold=${toString (check.latencyThreshold or 100)}
        success_threshold=${toString (check.successRateThreshold or 95)}
        cache_threshold=${toString (check.cacheHitRateThreshold or 80)}

        echo "DNS resolver performance check"

        total_queries=0
        successful_queries=0
        total_latency=0

        # Test each query
        ${lib.concatStringsSep "\n" (map (query: ''
          total_queries=$((total_queries + 1))
          start_time=$(date +%s%N)

          if timeout ${timeout} dig @localhost ${query} +short >/dev/null 2>&1; then
            successful_queries=$((successful_queries + 1))
            end_time=$(date +%s%N)
            latency=$(( (end_time - start_time) / 1000000 ))
            total_latency=$((total_latency + latency))
          fi
        '') check.queries)}

        # Calculate metrics
        if [ $total_queries -gt 0 ]; then
          success_rate=$((successful_queries * 100 / total_queries))
          avg_latency=$((total_latency / successful_queries))

          echo "Success rate: $success_rate%, Average latency: $avg_latency ms"

          # Check thresholds
          if [ $success_rate -lt $success_threshold ]; then
            echo "Success rate $success_rate% below threshold $success_threshold%"
            exit 1
          fi

          if [ $avg_latency -gt $latency_threshold ]; then
            echo "Average latency $avg_latency ms above threshold $latency_threshold ms"
            exit 1
          fi
        else
          echo "No queries to test"
          exit 1
        fi

        echo "DNS resolver performance check passed"
      ''
    else if check.type == "dhcp-server" then
      ''
        # DHCP server health check
        interface=${check.interface}

        echo "DHCP server health check on interface $interface"

        # Lease check (if enabled)
        ${if check.leaseCheck or true then ''
          # Check if DHCP server is responding (simplified - check if process exists)
          if ! pgrep -f "dhcp" >/dev/null 2>&1; then
            echo "DHCP server process not found"
            exit 1
          fi
        '' else ""}

        # Pool utilization check (if specified)
        ${if check.poolUtilization or null != null then ''
          # This would require parsing DHCP lease files
          # Placeholder for pool utilization check
          echo "Pool utilization check not implemented"
        '' else ""}

        # Response time check (if specified)
        ${if check.responseTime or null != null then ''
          # This would require sending DHCP discover and measuring response time
          # Placeholder for response time check
          echo "Response time check not implemented"
        '' else ""}

        echo "DHCP server check passed"
      ''
    else if check.type == "dhcp-database" then
      ''
        # DHCP database integrity check
        db_path=${check.path}

        echo "DHCP database integrity check: $db_path"

        # Basic file existence check
        if [ ! -f "$db_path" ]; then
          echo "DHCP database file not found: $db_path"
          exit 1
        fi

        # Database integrity check
        if ! timeout ${timeout} sqlite3 "$db_path" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
          echo "DHCP database integrity check failed"
          exit 1
        fi

        # Lease count check (if specified)
        ${if check.leaseCount or null != null then ''
          lease_count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM leases;" 2>/dev/null || echo "0")
          if [ "$lease_count" -lt ${toString check.leaseCount} ]; then
            echo "Lease count $lease_count below expected ${toString check.leaseCount}"
            exit 1
          fi
        '' else ""}

        # Conflict check (if enabled)
        ${if check.conflictCheck or false then ''
          conflict_count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM conflicts;" 2>/dev/null || echo "0")
          if [ "$conflict_count" -gt 0 ]; then
            echo "Found $conflict_count lease conflicts"
            exit 1
          fi
        '' else ""}

        echo "DHCP database check passed"
      ''
    else if check.type == "ids" then
      ''
        # IDS health check
        process=${check.process or "suricata"}

        echo "IDS health check for process $process"

        # Process check
        if ! pgrep -f "$process" >/dev/null 2>&1; then
          echo "IDS process $process not found"
          exit 1
        fi

        # Rules loaded check (if specified)
        ${if check.rulesLoaded or false then ''
          # Check if rules are loaded (simplified - check for rules file)
          if [ ! -f "/var/lib/suricata/rules/suricata.rules" ]; then
            echo "IDS rules file not found"
            exit 1
          fi
        '' else ""}

        # Packet rate check (if specified)
        ${if check.packetRate or null != null then ''
          # This would require parsing IDS statistics
          echo "Packet rate check not implemented"
        '' else ""}

        # Drop rate check (if specified)
        ${if check.dropRate or null != null then ''
          # This would require parsing IDS statistics
          echo "Drop rate check not implemented"
        '' else ""}

        echo "IDS check passed"
      ''
    else if check.type == "firewall" then
      ''
        # Firewall rules health check
        table=${check.table or "filter"}

        echo "Firewall rules check for table $table"

        # Basic iptables check
        if ! iptables -t $table -L >/dev/null 2>&1; then
          echo "Cannot access iptables table $table"
          exit 1
        fi

        # Chain check (if specified)
        ${if check.chain or null != null then ''
          if ! iptables -t $table -L ${check.chain} >/dev/null 2>&1; then
            echo "Chain ${check.chain} not found in table $table"
            exit 1
          fi
        '' else ""}

        # Rule count check (if specified)
        ${if check.ruleCount or null != null then ''
          rule_count=$(iptables -t $table -L | grep -c "^-")
          if [ "$rule_count" -lt ${toString check.ruleCount} ]; then
            echo "Rule count $rule_count below expected ${toString check.ruleCount}"
            exit 1
          fi
        '' else ""}

        # Policy check (if enabled)
        ${if check.policyCheck or false then ''
          # Check default policies are not ACCEPT
          if iptables -t $table -L | grep -q "policy ACCEPT"; then
            echo "Firewall has ACCEPT policy - may be too permissive"
            exit 1
          fi
        '' else ""}

        echo "Firewall check passed"
      ''
    else if check.type == "system" then
      ''
        # System resource health check
        resource=${check.resource}
        threshold=${toString (check.threshold or 80)}
        warning=${toString (check.warning or 70)}
        critical=${toString (check.critical or 90)}

        echo "System resource check: $resource (threshold: $threshold%)"

        case "$resource" in
          "cpu")
            # CPU usage check
            cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
            echo "CPU usage: $cpu_usage%"
            if [ $(echo "$cpu_usage > $critical" | bc -l 2>/dev/null || echo "0") -eq 1 ]; then
              echo "CPU usage $cpu_usage% exceeds critical threshold $critical%"
              exit 1
            fi
            echo "System CPU check passed ($cpu_usage%)"
            ;;
          "memory")
            # Memory usage check
            memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
            echo "Memory usage: $memory_usage%"
            if [ $(echo "$memory_usage > $critical" | bc -l 2>/dev/null || echo "0") -eq 1 ]; then
              echo "Memory usage $memory_usage% exceeds critical threshold $critical%"
              exit 1
            fi
            echo "System memory check passed ($memory_usage%)"
            ;;
          "disk")
            # Disk usage check (root filesystem)
            disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
            echo "Disk usage: $disk_usage%"
            if [ $(echo "$disk_usage > $critical" | bc -l 2>/dev/null || echo "0") -eq 1 ]; then
              echo "Disk usage $disk_usage% exceeds critical threshold $critical%"
              exit 1
            fi
            echo "System disk check passed ($disk_usage%)"
            ;;
          "temperature")
            # Temperature check (if sensors available)
            temp=$(sensors 2>/dev/null | grep -o "[0-9]*\.[0-9]*°C" | head -1 | sed 's/°C//')
            if [ -n "$temp" ]; then
              echo "Temperature: $temp°C"
              if [ $(echo "$temp > 70" | bc -l 2>/dev/null || echo "0") -eq 1 ]; then
                echo "Temperature $temp°C exceeds threshold"
                exit 1
              fi
              echo "System temperature check passed ($temp°C)"
            else
              echo "System temperature check passed (no sensors available)"
            fi
            ;;
          *)
            echo "Unknown resource type: $resource"
            exit 1
            ;;
        esac
      ''
    else if check.type == "database" then
      ''
        # Database integrity health check
        db_path=${check.path}
        check_type=${check.checkType or "integrity"}

        echo "Database check: $db_path (type: $check_type)"

        # File existence check
        if [ ! -f "$db_path" ]; then
          echo "Database file not found: $db_path"
          exit 1
        fi

        case "$check_type" in
          "integrity")
            # SQLite integrity check
            if ! timeout ${timeout} sqlite3 "$db_path" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
              echo "Database integrity check failed"
              exit 1
            fi
            ;;
          "connection")
            # Connection test
            if ! timeout ${timeout} sqlite3 "$db_path" "SELECT 1;" >/dev/null 2>&1; then
              echo "Database connection test failed"
              exit 1
            fi
            ;;
          "table")
            # Table existence check
            ${if check.tableCheck or null != null then ''
              if ! timeout ${timeout} sqlite3 "$db_path" "SELECT name FROM sqlite_master WHERE type='table' AND name='${check.tableCheck}';" | grep -q "${check.tableCheck}"; then
                echo "Table ${check.tableCheck} not found"
                exit 1
              fi
            '' else ""}
            ;;
          *)
            echo "Unknown database check type: $check_type"
            exit 1
            ;;
        esac

        echo "Database check passed"
      ''
    else if check.type == "port" then
      ''
        # Port connectivity health check
        protocol=${check.protocol or "tcp"}
        host=${check.host or "localhost"}

        echo "Port connectivity check: $host:${toString check.port} ($protocol)"

        if [ "$protocol" = "tcp" ]; then
          timeout ${timeout} nc -zv "$host" ${toString check.port} >/dev/null 2>&1
        elif [ "$protocol" = "udp" ]; then
          timeout ${timeout} nc -zuv "$host" ${toString check.port} >/dev/null 2>&1
        else
          echo "Unsupported protocol: $protocol"
          exit 1
        fi
      ''
    else if check.type == "script" then
      ''
        # Custom script health check
        expected_exit=${toString (check.expectedExitCode or 0)}

        echo "Custom script check: ${check.path}"

        if [ ! -x "${check.path}" ]; then
          echo "Script ${check.path} not found or not executable"
          exit 1
        fi

        # Run script with timeout
        exit_code=0
        timeout ${timeout} ${check.path} ${lib.concatStringsSep " " (check.args or [])} >/dev/null 2>&1 || exit_code=$?

        if [ "$exit_code" -ne "$expected_exit" ]; then
          echo "Script exited with code $exit_code, expected $expected_exit"
          exit 1
        fi

        echo "Script check passed"
      ''
    else if check.type == "http" then
      ''
        # HTTP endpoint health check
        method=${check.method or "GET"}
        expected_status=${toString (check.expectedStatus or 200)}

        echo "HTTP check: ${check.method or "GET"} ${check.url}"

        # Use curl for HTTP check
        response=$(timeout ${timeout} curl -s -o /dev/null -w "%{http_code}" \
          ${if check.method or null != null then "-X ${check.method}" else ""} \
          ${lib.concatStringsSep " " (map (h: "-H '${h}'") (check.headers or []))} \
          "${check.url}")

        if [ "$response" != "$expected_status" ]; then
          echo "HTTP status $response, expected $expected_status"
          exit 1
        fi

        # Content check (if specified)
        ${if check.expectedContent or null != null then ''
          content=$(timeout ${timeout} curl -s "${check.url}")
          if ! echo "$content" | grep -q "${check.expectedContent}"; then
            echo "Response does not contain expected content"
            exit 1
          fi
        '' else ""}

        echo "HTTP check passed"
      ''
    else if check.type == "metric" then
      ''
        # Metric-based health check
        metric=${check.metric}
        threshold=${toString (check.threshold or 0)}
        operator=${check.operator or "gt"}
        window=${check.window or "5m"}
        source=${check.source or "prometheus"}

        echo "Metric check: $metric $operator $threshold (window: $window)"

        # This would integrate with monitoring systems
        # Placeholder implementation
        case "$source" in
          "prometheus")
            # Query Prometheus for metric
            # This requires prometheus client or API access
            echo "Prometheus metric check not implemented"
            ;;
          "system")
            # System metric check
            case "$metric" in
              "load_average")
                load=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | sed 's/ //g')
                ;;
              "memory_free")
                mem_free=$(free -m | grep '^Mem:' | awk '{print $4}')
                ;;
              *)
                echo "Unknown system metric: $metric"
                exit 1
                ;;
            esac

            # Apply operator
            case "$operator" in
              "gt")
                if ! [ $(echo "$load > $threshold" | bc -l 2>/dev/null || echo "0") -eq 1 ]; then
                  echo "Metric $metric ($load) not greater than $threshold"
                  exit 1
                fi
                ;;
              "lt")
                if ! [ $(echo "$load < $threshold" | bc -l 2>/dev/null || echo "0") -eq 1 ]; then
                  echo "Metric $metric ($load) not less than $threshold"
                  exit 1
                fi
                ;;
              *)
                echo "Unsupported operator: $operator"
                exit 1
                ;;
            esac
            ;;
          *)
            echo "Unknown metric source: $source"
            exit 1
            ;;
        esac

        echo "Metric check passed"
      ''
    else
      throw "Unsupported health check type: ${check.type}";

  # Generate service health check script
  generateServiceHealthCheckScript =
    serviceName: serviceConfig:
    let
      checkScripts = map generateHealthCheckScript serviceConfig.checks;
      allChecks = concatStringsSep "\n" (
        map (script: ''
          if ! ( ${script} ); then
            echo "Health check failed for ${serviceName}"
            exit 1
          fi
        '') checkScripts
      );
    in
    ''
      #!/bin/sh
      set -x

      echo "Running health checks for ${serviceName}..."

      ${allChecks}

      echo "All health checks passed for ${serviceName}"
      exit 0
    '';

  # Generate health check systemd service
  generateHealthCheckService =
    serviceName: serviceConfig:
    let
      scriptPath = "/run/gateway-health-checks/${serviceName}-check.sh";
      interval = serviceConfig.interval or "30s";
      timeout = serviceConfig.timeout or "10s";
    in
    {
      name = "gateway-health-check-${serviceName}";
      value = {
        description = "Health check for ${serviceName} service";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = scriptPath;
          TimeoutStartSec = timeout;
          User = "root";
          Group = "root";
        };
      };
    };

  # Generate health check systemd timer
  generateHealthCheckTimer =
    serviceName: serviceConfig:
    let
      interval = serviceConfig.interval or "30s";
      serviceName = "gateway-health-check-${serviceName}";
    in
    {
      name = "${serviceName}-timer";
      value = {
        description = "Timer for ${serviceName} health checks";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = interval;
          Persistent = true;
        };
      };
    };

  # Generate Prometheus metrics for health checks
  generateHealthCheckMetrics =
    healthChecks:
    let
      serviceMetrics = mapAttrsToList (serviceName: serviceConfig: ''
        # HELP gateway_health_check_status Health check status (1 = healthy, 0 = unhealthy)
        # TYPE gateway_health_check_status gauge
        gateway_health_check_status{service="${serviceName}"} 1

        # HELP gateway_health_check_last_success_timestamp Last successful health check timestamp
        # TYPE gateway_health_check_last_success_timestamp gauge
        gateway_health_check_last_success_timestamp{service="${serviceName}"} $(date +%s)

        # HELP gateway_health_check_check_count Number of health checks for service
        # TYPE gateway_health_check_check_count gauge
        gateway_health_check_check_count{service="${serviceName}"} ${toString (builtins.length serviceConfig.checks)}
      '') healthChecks;
    in
    concatStringsSep "\n" serviceMetrics;

  # Default health check configurations for common services
  defaultHealthChecks = {
    # Network components
    "network-interfaces" = {
      checks = [
        {
          type = "interface";
          interface = "eth0";
          expectedState = "UP";
          linkQuality = true;
        }
        {
          type = "interface";
          interface = "eth1";
          expectedState = "UP";
          linkQuality = true;
        }
      ];
      interval = "30s";
      timeout = "5s";
    };

    "routing" = {
      checks = [
        {
          type = "routing";
          route = "default";
          checkType = "basic";
        }
        {
          type = "connectivity";
          target = "8.8.8.8";
          protocol = "icmp";
          expectedLatency = 100;
        }
      ];
      interval = "60s";
      timeout = "10s";
    };

    "firewall" = {
      checks = [
        {
          type = "firewall";
          table = "filter";
          policyCheck = true;
        }
        {
          type = "firewall";
          table = "nat";
          chain = "POSTROUTING";
        }
      ];
      interval = "300s";
      timeout = "30s";
    };

    # DNS components
    "dns-resolution" = {
      checks = [
        {
          type = "query";
          target = "localhost";
          query = "example.com";
          recordType = "A";
          timeout = "2s";
        }
        {
          type = "query";
          target = "localhost";
          query = "google.com";
          recordType = "A";
          timeout = "2s";
        }
      ];
      interval = "30s";
      timeout = "5s";
    };

    "dns-cache" = {
      checks = [
        {
          type = "resolver";
          queries = [ "example.com" "google.com" "cloudflare.com" ];
          latencyThreshold = 50;
          successRateThreshold = 99;
          cacheHitRateThreshold = 70;
        }
      ];
      interval = "60s";
      timeout = "30s";
    };

    "dns-zones" = {
      checks = [
        {
          type = "zone";
          zone = "lan.local";
          soaCheck = true;
          serialCheck = true;
        }
      ];
      interval = "300s";
      timeout = "30s";
    };

    # DHCP components
    "dhcp-server" = {
      checks = [
        {
          type = "dhcp-server";
          interface = "eth0";
          leaseCheck = true;
        }
        {
          type = "port";
          port = 67;
          protocol = "udp";
          host = "localhost";
        }
      ];
      interval = "60s";
      timeout = "10s";
    };

    "dhcp-database" = {
      checks = [
        {
          type = "dhcp-database";
          path = "/var/lib/kea/dhcp4.leases";
          checkType = "integrity";
          conflictCheck = true;
        }
        {
          type = "process";
          name = "kea-dhcp4";
          memoryLimit = 100;
        }
      ];
      interval = "300s";
      timeout = "30s";
    };

    "dhcp-leases" = {
      checks = [
        {
          type = "dhcp-database";
          path = "/var/lib/kea/dhcp4.leases";
          leaseCount = 1;
        }
      ];
      interval = "300s";
      timeout = "30s";
    };

    # Security components
    "ids" = {
      checks = [
        {
          type = "ids";
          process = "suricata";
          rulesLoaded = true;
        }
        {
          type = "process";
          name = "suricata";
          cpuLimit = 80;
          memoryLimit = 500;
        }
        {
          type = "filesystem";
          path = "/var/log/suricata";
          checkType = "directory";
        }
      ];
      interval = "60s";
      timeout = "10s";
    };

    "threat-detection" = {
      checks = [
        {
          type = "metric";
          metric = "ids_alerts";
          operator = "lt";
          threshold = 100;
          window = "1h";
          source = "system";
        }
      ];
      interval = "300s";
      timeout = "30s";
    };

    # System components
    "cpu" = {
      checks = [
        {
          type = "system";
          resource = "cpu";
          threshold = 80;
          warning = 70;
          critical = 90;
        }
      ];
      interval = "30s";
      timeout = "5s";
    };

    "memory" = {
      checks = [
        {
          type = "system";
          resource = "memory";
          threshold = 85;
          warning = 75;
          critical = 95;
        }
      ];
      interval = "30s";
      timeout = "5s";
    };

    "disk" = {
      checks = [
        {
          type = "system";
          resource = "disk";
          threshold = 90;
          warning = 80;
          critical = 95;
        }
        {
          type = "filesystem";
          path = "/";
          minFreeSpace = "1G";
        }
        {
          type = "filesystem";
          path = "/var";
          minFreeSpace = "500M";
        }
      ];
      interval = "300s";
      timeout = "30s";
    };

    "temperature" = {
      checks = [
        {
          type = "system";
          resource = "temperature";
          threshold = 70;
          warning = 60;
          critical = 80;
        }
      ];
      interval = "300s";
      timeout = "30s";
    };

    # Monitoring components
    "monitoring" = {
      checks = [
        {
          type = "port";
          port = 9100;
          protocol = "tcp";
          host = "localhost";
        } # node-exporter
        {
          type = "port";
          port = 9090;
          protocol = "tcp";
          host = "localhost";
        } # prometheus
        {
          type = "http";
          url = "http://localhost:9090/-/healthy";
          expectedStatus = 200;
        }
      ];
      interval = "30s";
      timeout = "10s";
    };
  };

in
{
  inherit
    healthCheckTypes
    validateHealthCheck
    validateServiceHealthChecks
    generateHealthCheckScript
    generateServiceHealthCheckScript
    generateHealthCheckService
    generateHealthCheckTimer
    generateHealthCheckMetrics
    defaultHealthChecks
    ;

  # Main function to process health checks configuration
  processHealthChecks =
    healthChecks:
    let
      validatedChecks = mapAttrs validateServiceHealthChecks healthChecks;
      services = mapAttrs generateHealthCheckService validatedChecks;
      timers = mapAttrs generateHealthCheckTimer validatedChecks;
      scripts = mapAttrs generateServiceHealthCheckScript validatedChecks;
      metrics = generateHealthCheckMetrics validatedChecks;
    in
    {
      inherit
        validatedChecks
        services
        timers
        scripts
        metrics
        ;
    };

  # Merge user health checks with defaults
  mergeHealthChecks =
    userChecks:
    let
      merged = defaultHealthChecks // userChecks;
    in
    mapAttrs (
      serviceName: userConfig:
      let
        defaultConfig = defaultHealthChecks.${serviceName} or { };
        mergedConfig = defaultConfig // userConfig;
        mergedChecks =
          if userConfig ? checks then
            userConfig.checks
          else if defaultConfig ? checks then
            defaultConfig.checks
          else
            [ ];
      in
      mergedConfig // { checks = mergedChecks; }
    ) merged;
}
