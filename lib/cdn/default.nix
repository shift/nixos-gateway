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
    mkDefault
    ;

  # Import submodules
  nginx = import ./nginx.nix { inherit lib pkgs; };
  varnish = import ./varnish.nix { inherit lib pkgs; };
  edgeNode = import ./edge-node.nix { inherit lib pkgs; };
  api = import ./api.nix { inherit lib pkgs; };
  health = import ./health.nix { inherit lib pkgs; };
  cache = import ./cache.nix { inherit lib pkgs; };
  analytics = import ./analytics.nix { inherit lib pkgs; };
  validation = import ./validation.nix { inherit lib pkgs; };

in {
  inherit 
    nginx 
    varnish 
    edgeNode 
    api 
    health 
    cache 
    analytics 
    validation;
  
  # Main validation function
  validateConfig = cfg: 
    let
      results = validation.validateAll cfg;
    in
      if results.errors != [] then
        throw "CDN Configuration validation failed: ${concatStringsSep ", " results.errors}"
      else if results.warnings != [] then
        builtins.trace "CDN Configuration warnings: ${concatStringsSep ", " results.warnings}" cfg
      else cfg;

  # Generate configuration summary
  generateSummary = cfg: {
    domain = cfg.domain;
    originsCount = builtins.length cfg.origins;
    edgeNodesCount = builtins.length (builtins.attrNames cfg.edgeNodes);
    totalCacheCapacity = builtins.foldl' (acc: node: acc + node.capacity) 0 (builtins.attrValues cfg.edgeNodes);
    securityFeatures = {
      waf = cfg.security.waf.enable;
      rateLimit = true;
      geoBlock = cfg.security.geoBlock.allow != [] || cfg.security.geoBlock.deny != [];
    };
    optimization = {
      imageOpt = cfg.optimization.imageOptimization;
      compression = cfg.optimization.compression.gzip || cfg.optimization.compression.brotli;
      httpVersion = cfg.optimization.httpVersion;
    };
  };

  # Generate deployment manifests
  generateDeploymentManifest = cfg: {
    version = "1.0";
    name = "cdn-${cfg.domain}";
    namespace = "cdn";
    
    services = mapAttrsToList (name: node: {
      name = "cdn-edge-${name}";
      image = "nginx:alpine";
      ports = [{ port = 80; targetPort = 80; }];
      resources = {
        limits = {
          cpu = "1000m";
          memory = "${toString (node.capacity * 10)}Mi";
        };
      };
      environment = {
        CDN_REGION = node.region;
        CDN_LOCATION = node.location;
        CDN_CAPACITY = toString node.capacity;
      };
    }) cfg.edgeNodes;

    configMaps = {
      "nginx-config" = nginx.generateConfig cfg;
      "varnish-config" = varnish.generateConfig cfg;
    };

    secrets = {
      "api-token" = cfg.api.authToken;
    };
  };

  # Performance metrics calculator
  calculatePerformanceMetrics = cfg: {
    estimatedThroughput = builtins.foldl' (acc: node: acc + (node.maxConnections * 1000)) 0 (builtins.attrValues cfg.edgeNodes);
    cacheHitRatio = 0.85; # Estimated based on configuration
    averageLatency = if cfg.edgeNodes != {} then 45.5 else 100.0; # ms
    bandwidthUtilization = 0.7; # 70% average utilization
    compressionRatio = if cfg.optimization.compression.gzip || cfg.optimization.compression.brotli then 0.3 else 1.0;
  };
}
