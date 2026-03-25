{ lib, pkgs }:

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
    flatten
    unique
    elem
    head
    last
    length
    all
    any
    hasAttr
    attrNames
    genAttrs
    optional
    optionalString
    stringLength
    substring
    splitString
    replaceStrings
    toLower
    foldl'
    ;

  # Enhanced service reload capabilities definition
  reloadCapabilities = {
    dns = {
      supportsReload = true;
      reloadCommand = "systemctl reload knot";
      validationCommand = "knotc conf-check";
      configFiles = [
        "/etc/knot/knotd.conf"
        "/var/lib/knot/zones/*.zone"
      ];
      dependencies = [ ];
      reloadTimeout = 30;
      healthCheckDelay = 5;
      rollbackFiles = [ "/etc/knot/knotd.conf" ];
      rollbackCommand = "systemctl restart knot";
    };
    dhcp = {
      supportsReload = true;
      reloadCommand = "systemctl reload kea-dhcp4-server kea-dhcp6-server";
      validationCommand = "kea-dhcp4 -t /etc/kea/dhcp4-server.conf && kea-dhcp6 -t /etc/kea/dhcp6-server.conf";
      configFiles = [
        "/etc/kea/dhcp4-server.conf"
        "/etc/kea/dhcp6-server.conf"
      ];
      dependencies = [ ];
      reloadTimeout = 45;
      healthCheckDelay = 10;
      rollbackFiles = [
        "/etc/kea/dhcp4-server.conf"
        "/etc/kea/dhcp6-server.conf"
      ];
      rollbackCommand = "systemctl restart kea-dhcp4-server kea-dhcp6-server";
    };
    firewall = {
      supportsReload = true;
      reloadCommand = "nft -f /etc/nftables.conf";
      validationCommand = "nft -c /etc/nftables.conf";
      configFiles = [ "/etc/nftables.conf" ];
      dependencies = [ ];
      reloadTimeout = 15;
      healthCheckDelay = 2;
      rollbackFiles = [ "/etc/nftables.conf" ];
      rollbackCommand = "systemctl restart nftables";
    };
    ids = {
      supportsReload = true;
      reloadCommand = "systemctl reload suricata";
      validationCommand = "suricata -T -c /etc/suricata/suricata.yaml";
      configFiles = [
        "/etc/suricata/suricata.yaml"
        "/etc/suricata/rules/*.rules"
      ];
      dependencies = [ "network" ];
      reloadTimeout = 60;
      healthCheckDelay = 15;
      rollbackFiles = [ "/etc/suricata/suricata.yaml" ];
      rollbackCommand = "systemctl restart suricata";
    };
    network = {
      supportsReload = false;
      reloadCommand = "";
      validationCommand = "";
      configFiles = [ ];
      dependencies = [ ];
      reloadTimeout = 0;
      healthCheckDelay = 0;
      rollbackFiles = [ ];
      rollbackCommand = "";
      note = "Network changes require interface restart";
    };
    monitoring = {
      supportsReload = true;
      reloadCommand = "systemctl reload prometheus grafana";
      validationCommand = "promtool check config /etc/prometheus/prometheus.yml";
      configFiles = [
        "/etc/prometheus/prometheus.yml"
        "/etc/grafana/grafana.ini"
      ];
      dependencies = [ ];
      reloadTimeout = 30;
      healthCheckDelay = 5;
      rollbackFiles = [ "/etc/prometheus/prometheus.yml" ];
      rollbackCommand = "systemctl restart prometheus grafana";
    };
    vpn = {
      supportsReload = true;
      reloadCommand = "systemctl reload wireguard";
      validationCommand = "wg-quick strip wg0 > /dev/null";
      configFiles = [ "/etc/wireguard/wg0.conf" ];
      dependencies = [
        "network"
        "firewall"
      ];
      reloadTimeout = 20;
      healthCheckDelay = 5;
      rollbackFiles = [ "/etc/wireguard/wg0.conf" ];
      rollbackCommand = "systemctl restart wireguard";
    };
    tailscale = {
      supportsReload = true;
      reloadCommand = "tailscale up";
      validationCommand = "tailscale status";
      configFiles = [ "/etc/tailscale/tailscaled.conf" ];
      dependencies = [ "network" ];
      reloadTimeout = 30;
      healthCheckDelay = 10;
      rollbackFiles = [ "/etc/tailscale/tailscaled.conf" ];
      rollbackCommand = "systemctl restart tailscaled";
    };
  };

  # Configuration diff detection
  #
  # Compares two Nix config attrsets for a given service by hashing their
  # JSON-serialised representations.  This is pure-eval (no file I/O) and
  # deterministic: the same config always produces the same hash.
  #
  # Returns:
  #   { changed :: bool, message :: string, files? :: [string] }
  #   changed = true  → configs differ and a reload is warranted
  #   changed = false → configs are identical, no reload needed
  generateConfigDiff =
    oldConfig: newConfig: service:
    let
      serviceConfig = reloadCapabilities.${service} or { configFiles = [ ]; };
      hasConfigFiles = builtins.length serviceConfig.configFiles > 0;

      # Serialise each config to JSON and hash; order-insensitive because
      # builtins.toJSON sorts attrset keys lexicographically.
      hashOf = cfg: builtins.hashString "sha256" (builtins.toJSON cfg);
      oldHash = hashOf oldConfig;
      newHash = hashOf newConfig;
      changed = oldHash != newHash;
    in
    if !hasConfigFiles && !changed then
      {
        changed = false;
        message = "No config files registered and configs are identical for ${service}";
      }
    else if !changed then
      {
        changed = false;
        message = "Configuration unchanged for ${service} (hash: ${builtins.substring 0 8 newHash}…)";
        files = serviceConfig.configFiles;
      }
    else
      {
        changed = true;
        message = "Configuration changed for ${service} (${builtins.substring 0 8 oldHash}… → ${builtins.substring 0 8 newHash}…)";
        files = serviceConfig.configFiles;
      };

  # Validate configuration before reload
  validateConfig = service: ''
    echo "Validating ${service} configuration..."

    # Check if service supports validation
    ${lib.optionalString (reloadCapabilities.${service}.validationCommand != "") ''
      if ! ${reloadCapabilities.${service}.validationCommand}; then
        echo "❌ ${service} configuration validation failed"
        exit 1
      fi
      echo "✅ ${service} configuration validation passed"
    ''}

    # Check service health before reload
    if ! systemctl is-active --quiet ${service} 2>/dev/null; then
      echo "⚠️  ${service} is not currently active, proceeding with reload"
    fi
  '';

  # Generate enhanced reload script for a service
  generateReloadScript =
    service:
    let
      caps = getReloadCapabilities service;
    in
    ''
      #!/bin/sh
      set -e

      SERVICE="${service}"
      TIMEOUT=${toString caps.reloadTimeout}
      HEALTH_DELAY=${toString caps.healthCheckDelay}

      echo "Reloading $SERVICE configuration..."

      # Validate configuration if validation command is available
      if [ -n "${caps.validationCommand}" ]; then
        echo "Validating $SERVICE configuration..."
        if ! timeout 30 ${caps.validationCommand}; then
          echo "Configuration validation failed for $SERVICE"
          exit 1
        fi
        echo "Configuration validation passed for $SERVICE"
      fi

      # Create backup before reload
      /run/gateway-config-scripts/backup-${service}.sh

      # Reload the service
      echo "Executing reload command for $SERVICE..."
      if ! timeout "$TIMEOUT" ${caps.reloadCommand}; then
        echo "Reload command failed for $SERVICE"
        echo "Attempting rollback..."
        /run/gateway-config-scripts/rollback-${service}.sh
        exit 1
      fi

      echo "Reload command completed for $SERVICE"

      # Wait for health check delay
      if [ "$HEALTH_DELAY" -gt 0 ]; then
        echo "Waiting $HEALTH_DELAY seconds for service to stabilize..."
        sleep "$HEALTH_DELAY"
      fi

      # Run health checks if available
      HEALTH_CHECK_SCRIPT="/run/gateway-health-checks/${service}-check.sh"
      if [ -f "$HEALTH_CHECK_SCRIPT" ]; then
        echo "Running health checks for $SERVICE..."
        if ! "$HEALTH_CHECK_SCRIPT"; then
          echo "Health checks failed for $SERVICE"
          echo "Attempting rollback..."
          /run/gateway-config-scripts/rollback-${service}.sh
          exit 1
        fi
        echo "Health checks passed for $SERVICE"
      fi

      echo "Reload completed successfully for $SERVICE"
    '';

  # Get reload capabilities for a service
  getReloadCapabilities =
    service:
    reloadCapabilities.${service} or {
      supportsReload = false;
      reloadCommand = "";
      validationCommand = "";
      configFiles = [ ];
      dependencies = [ ];
      reloadTimeout = 30;
      healthCheckDelay = 5;
      rollbackFiles = [ ];
    };

  # Get services that depend on a given service
  getDependentServices =
    service:
    let
      deps = mapAttrsToList (
        serviceName: caps: if elem service caps.dependencies then serviceName else null
      ) reloadCapabilities;
    in
    filter (s: s != null) deps;

  # Enhanced dependency-aware reload order using topological sort
  generateReloadOrder =
    services:
    let
      # Topological sort implementation
      visit =
        visited: currentPath: service:
        if elem service visited then
          visited
        else if elem service currentPath then
          throw "Circular dependency detected involving ${service}"
        else
          let
            caps = getReloadCapabilities service;
            deps = filter (dep: elem dep services) caps.dependencies;
            visitedWithDeps = foldl' (acc: dep: visit acc (currentPath ++ [ service ]) dep) visited deps;
          in
          visitedWithDeps ++ [ service ];

      sortServices =
        services:
        let
          sorted = foldl' (visit [ ]) [ ] services;
        in
        unique (filter (svc: elem svc services) sorted);
    in
    sortServices services;

  # Generate enhanced coordinated reload script
  generateCoordinatedReloadScript =
    services:
    let
      reloadOrder = generateReloadOrder services;
      reloadCommands = map (service: ''
        echo "=== Reloading ${service} ==="
        /run/gateway-config-scripts/reload-${service}.sh
        echo "=== ${service} reload completed ==="
        echo ""
      '') reloadOrder;
    in
    ''
      #!/bin/sh
      set -e

      SERVICES="''${1:-${concatStringsSep " " services}}"
      RELOAD_ORDER="${concatStringsSep " " reloadOrder}"

      echo "Starting coordinated reload for services: $SERVICES"
      echo "Reload order: $RELOAD_ORDER"
      echo ""

      # Check if all services support reload
      for service in $SERVICES; do
        if [ "$service" = "network" ]; then
          echo "Warning: Network service does not support hot reload, skipping"
          continue
        fi
      done

      # Execute reloads in dependency order
      ${concatStringsSep "\n" reloadCommands}

      echo "All reloads completed successfully"
    '';

  # Generate file hash for change detection
  generateFileHash = filePath: ''
    if [ -f "${filePath}" ]; then
      sha256sum "${filePath}" | cut -d' ' -f1
    else
      echo "missing"
    fi
  '';

  # Generate enhanced change detection script for a service
  generateChangeDetectionScript =
    service:
    let
      caps = getReloadCapabilities service;
      hashCommands = map (file: generateFileHash file) caps.configFiles;
    in
    ''
      #!/bin/sh
      set -e

      SERVICE="${service}"
      HASH_DIR="/var/lib/gateway-config-hashes"
      SERVICE_HASH_DIR="$HASH_DIR/$SERVICE"
      CURRENT_HASH_FILE="$SERVICE_HASH_DIR/current"
      PREV_HASH_FILE="$SERVICE_HASH_DIR/previous"

      # Create hash directory
      mkdir -p "$SERVICE_HASH_DIR"

      # Generate current hash
      CURRENT_HASH=$(
        ${concatStringsSep "\n" hashCommands} | sort | sha256sum | cut -d' ' -f1
      )

      # Load previous hash
      if [ -f "$CURRENT_HASH_FILE" ]; then
        PREV_HASH=$(cat "$CURRENT_HASH_FILE")
      else
        PREV_HASH=""
      fi

      # Check if configuration changed
      if [ "$CURRENT_HASH" != "$PREV_HASH" ]; then
        echo "Configuration changed for $SERVICE"
        echo "$PREV_HASH" > "$PREV_HASH_FILE"
        echo "$CURRENT_HASH" > "$CURRENT_HASH_FILE"
        exit 1  # Exit with 1 to indicate change
      else
        echo "No changes for $SERVICE"
        exit 0  # Exit with 0 to indicate no change
      fi
    '';

  # Generate global change detection script
  generateGlobalChangeDetectionScript =
    services:
    let
      serviceChecks = map (service: ''
        SERVICE="${service}"
        echo "Checking $SERVICE..."
        if /run/gateway-config-scripts/change-detection-${service}.sh; then
          echo "✅ $SERVICE: No changes"
        else
          echo "🔄 $SERVICE: Configuration changed"
          CHANGED_SERVICES="$CHANGED_SERVICES $SERVICE"
        fi
      '') services;
    in
    ''
      #!/bin/sh
      set -e

      CHANGED_SERVICES=""
      SERVICES="${concatStringsSep " " services}"

      echo "Checking for configuration changes..."
      echo ""

      ${concatStringsSep "\n" serviceChecks}

      echo ""
      if [ -n "$CHANGED_SERVICES" ]; then
        echo "Services with changes:$CHANGED_SERVICES"
        exit 1  # Exit with 1 to indicate changes detected
      else
        echo "No configuration changes detected"
        exit 0  # Exit with 0 to indicate no changes
      fi
    '';

  # Generate enhanced backup script for a service
  generateBackupScript =
    service:
    let
      caps = getReloadCapabilities service;
      backupCommands = map (file: ''
        if [ -f "${file}" ]; then
          cp "${file}" "$BACKUP_DIR/$(basename ${file})"
          echo "Backed up ${file}"
        fi
      '') caps.rollbackFiles;
    in
    ''
      #!/bin/sh
      set -e

      SERVICE="${service}"
      BACKUP_DIR="/var/lib/gateway-config-backup/$SERVICE/$(date +%Y%m%d_%H%M%S)"
      CURRENT_DIR="/var/lib/gateway-config-current/$SERVICE"

      # Create backup directory
      mkdir -p "$BACKUP_DIR"
      mkdir -p "$(dirname "$CURRENT_DIR")"

      # Backup configuration files
      ${concatStringsSep "\n" backupCommands}

      # Create symlink to current backup
      rm -f "$CURRENT_DIR"
      ln -sf "$BACKUP_DIR" "$CURRENT_DIR"

      echo "Backup completed for $SERVICE: $BACKUP_DIR"
    '';

  # Generate enhanced rollback script for a service
  generateRollbackScript =
    service:
    let
      caps = getReloadCapabilities service;
      restoreCommands = map (file: ''
        if [ -f "$BACKUP_DIR/$(basename ${file})" ]; then
          cp "$BACKUP_DIR/$(basename ${file})" "${file}"
          echo "Restored ${file}"
        else
          echo "Warning: No backup found for ${file}"
        fi
      '') caps.rollbackFiles;
    in
    ''
      #!/bin/sh
      set -e

      SERVICE="''${1:-${service}}"
      CURRENT_DIR="/var/lib/gateway-config-current/$SERVICE"

      if [ ! -L "$CURRENT_DIR" ]; then
        echo "No current backup found for $SERVICE"
        exit 1
      fi

      BACKUP_DIR=$(readlink "$CURRENT_DIR")

      if [ ! -d "$BACKUP_DIR" ]; then
        echo "Backup directory not found: $BACKUP_DIR"
        exit 1
      fi

      echo "Rolling back $SERVICE to backup: $BACKUP_DIR"

      # Restore configuration files
      ${concatStringsSep "\n" restoreCommands}

      # Restart service
      echo "Restarting $SERVICE..."
      if ${reloadCapabilities.${service}.rollbackCommand}; then
        echo "✅ $SERVICE restarted successfully"
      else
        echo "❌ Failed to restart $SERVICE"
        exit 1
      fi

      echo "✅ Rollback completed for $SERVICE"
    '';

  # Generate cleanup script for old backups
  generateCleanupScript = retentionDays: ''
    #!/bin/sh
    set -e

    BACKUP_DIR="/var/lib/gateway-config-backup"
    RETENTION_DAYS=${toString retentionDays}

    echo "Cleaning up backups older than $RETENTION_DAYS days..."

    if [ -d "$BACKUP_DIR" ]; then
      find "$BACKUP_DIR" -type d -mtime "+$RETENTION_DAYS" -exec rm -rf {} \; 2>/dev/null || true
      echo "Backup cleanup completed"
    else
      echo "Backup directory not found: $BACKUP_DIR"
    fi
  '';

in
{
  inherit
    reloadCapabilities
    generateConfigDiff
    generateReloadScript
    generateCoordinatedReloadScript
    generateChangeDetectionScript
    generateRollbackScript
    generateReloadOrder
    validateConfig
    ;

  # New enhanced functions
  inherit
    getReloadCapabilities
    getDependentServices
    generateBackupScript
    generateCleanupScript
    generateGlobalChangeDetectionScript
    ;

  # Main reload orchestration function
  orchestrateReload =
    {
      services ? [ ],
      allServices ? false,
      dryRun ? false,
    }:
    let
      servicesToReload = if allServices then builtins.attrNames reloadCapabilities else services;
      reloadOrder = generateReloadOrder servicesToReload;
    in
    {
      reloadOrder = reloadOrder;
      scripts = builtins.listToAttrs (
        map (service: {
          name = service;
          value = generateReloadScript service;
        }) servicesToReload
      );
      coordinatedScript = generateCoordinatedReloadScript servicesToReload;
      changeDetectionScript = generateChangeDetectionScript;
      rollbackScripts = builtins.listToAttrs (
        map (service: {
          name = service;
          value = generateRollbackScript service;
        }) servicesToReload
      );
      backupScripts = builtins.listToAttrs (
        map (service: {
          name = service;
          value = generateBackupScript service;
        }) servicesToReload
      );
    };

  # Check if service supports reload
  supportsReload = service: (reloadCapabilities.${service} or { }).supportsReload or false;

  # Validate reload configuration
  validateReloadConfig =
    config:
    let
      hasValidServices = config ? services && builtins.isList config.services;
      validServices = builtins.filter (
        svc: builtins.elem svc (builtins.attrNames reloadCapabilities)
      ) config.services;
      hasValidOptions = config ? options && builtins.isAttrs config.options;
    in
    assert lib.assertMsg hasValidServices "Reload config must have 'services' list";
    assert lib.assertMsg (builtins.length validServices == builtins.length config.services)
      "Invalid services in reload config: ${
        builtins.toString (builtins.filter (svc: !builtins.elem svc validServices) config.services)
      }";
    config // { services = validServices; };

  # Main processing function for module integration
  processConfigReload =
    config:
    let
      enabledServices = config.services or [ ];
      autoReload = config.enableAutoReload or false;
      changeDetection = config.enableChangeDetection or false;
      rollback = config.enableRollback or true;
      backupRetention = config.backupRetention or "7d";
      reloadTimeout = config.reloadTimeout or 300;
      healthCheckDelay = config.healthCheckDelay or 10;

      # Generate all scripts for enabled services
      changeDetectionScripts = mapAttrs (service: generateChangeDetectionScript) (
        genAttrs enabledServices (service: service)
      );

      backupScripts = mapAttrs (service: generateBackupScript) (
        genAttrs enabledServices (service: service)
      );

      rollbackScripts = mapAttrs (service: generateRollbackScript) (
        genAttrs enabledServices (service: service)
      );

      reloadScripts = mapAttrs (service: generateReloadScript) (
        genAttrs enabledServices (service: service)
      );

      coordinatedReloadScript = generateCoordinatedReloadScript enabledServices;
      cleanupScript = generateCleanupScript (
        if builtins.isString backupRetention then
          7 # Default to 7 days if string format
        else
          backupRetention
      );

      # Generate systemd path units for file watching
      pathUnits = mapAttrs (service: caps: {
        name = "gateway-config-watch-${service}.path";
        value = {
          description = "Watch ${service} configuration files for changes";
          wantedBy = [ "multi-user.target" ];
          pathConfig = {
            PathModified = caps.configFiles;
            Unit = "gateway-config-change-detection-${service}.service";
          };
        };
      }) (genAttrs enabledServices getReloadCapabilities);

      # Generate systemd service units for change detection
      changeDetectionServices = mapAttrs (service: script: {
        name = "gateway-config-change-detection-${service}.service";
        value = {
          description = "Detect configuration changes for ${service}";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "/run/gateway-config-scripts/change-detection-${service}.sh";
            User = "root";
            Group = "root";
          };
        };
      }) changeDetectionScripts;

    in
    {
      inherit
        enabledServices
        autoReload
        changeDetection
        rollback
        backupRetention
        reloadTimeout
        healthCheckDelay
        ;

      scripts = {
        changeDetection = changeDetectionScripts;
        backup = backupScripts;
        rollback = rollbackScripts;
        reload = reloadScripts;
        coordinatedReload = coordinatedReloadScript;
        cleanup = cleanupScript;
      };

      systemd = {
        paths = pathUnits;
        services = changeDetectionServices;
      };

      # Validation function
      validate =
        services:
        let
          invalidServices = filter (service: !(hasAttr service reloadCapabilities)) services;
          unsupportedServices = filter (service: !(getReloadCapabilities service).supportsReload) services;
        in
        {
          valid = invalidServices == [ ];
          invalidServices = invalidServices;
          unsupportedServices = unsupportedServices;
          errors =
            (
              if invalidServices != [ ] then
                [ "Unknown services: ${concatStringsSep ", " invalidServices}" ]
              else
                [ ]
            )
            ++ (
              if unsupportedServices != [ ] then
                [ "Services that don't support reload: ${concatStringsSep ", " unsupportedServices}" ]
              else
                [ ]
            );
        };
    };
}
