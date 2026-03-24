{ lib, ... }:

with lib;

{
  # Generate OpenTelemetry Collector Configuration
  mkOtelConfig = cfg: {
    receivers = {
      otlp = {
        protocols = {
          grpc = { };
          http = { };
        };
      };
    };

    processors = {
      batch = {
        timeout = cfg.collector.batch.timeout;
        send_batch_size = cfg.collector.batch.batchSize;
      };

      probabilistic_sampler = mkIf (cfg.collector.sampling.strategy == "probabilistic") {
        sampling_percentage = cfg.collector.sampling.probability * 100.0;
      };

      # Add more processors if needed for analysis/attributes
      attributes = {
        actions = [
          {
            key = "environment";
            value = "gateway";
            action = "insert";
          }
        ];
      };
    };

    exporters = {
      logging = {
        verbosity = "detailed";
      };
    }
    // (optionalAttrs cfg.integration.jaeger.enable {
      # Using jaeger exporter to support the legacy endpoint in requirements
      jaeger = {
        endpoint = cfg.collector.endpoint;
        tls = {
          insecure = true;
        };
      };
    });

    service = {
      pipelines = {
        traces = {
          receivers = [ "otlp" ];
          processors = [
            "batch"
            "attributes"
          ]
          ++ (optional (cfg.collector.sampling.strategy == "probabilistic") "probabilistic_sampler");
          exporters = [ "logging" ] ++ (optional cfg.integration.jaeger.enable "jaeger");
        };
      };
    };
  };

  # Helper to validate service specific overrides
  validateServiceOverrides =
    overrides: all (o: o.probability >= 0.0 && o.probability <= 1.0) (attrValues overrides);

  # Enhanced tracing utilities
  generateTraceId = builtins.substring 0 32 (builtins.hashString "sha256" (toString builtins.currentTime + toString (builtins.getEnv "RANDOM")));

  generateSpanId = builtins.substring 0 16 (builtins.hashString "sha256" (toString builtins.currentTime + toString (builtins.getEnv "RANDOM")));

  # Span creation helpers
  mkSpan = {
    traceId,
    spanId,
    parentSpanId ? null,
    name,
    serviceName,
    startTime ? builtins.currentTime,
    attributes ? {},
    kind ? "internal"
  }: {
    inherit traceId spanId parentSpanId name serviceName startTime attributes kind;
    status = "ok";
  };

  # Span finishing helper
  finishSpan = span: endTime: span // {
    endTime = endTime;
    duration = endTime - span.startTime;
  };

  # Attribute helpers
  mkStringAttribute = value: { stringValue = value; };
  mkIntAttribute = value: { intValue = value; };
  mkBoolAttribute = value: { boolValue = value; };
  mkDoubleAttribute = value: { doubleValue = value; };

  # Common span attributes
  commonAttributes = {
    service = mkStringAttribute;
    operation = mkStringAttribute;
    user = mkStringAttribute;
    client_ip = mkStringAttribute;
    server_ip = mkStringAttribute;
    protocol = mkStringAttribute;
    port = mkIntAttribute;
    bytes_sent = mkIntAttribute;
    bytes_received = mkIntAttribute;
    duration_ms = mkDoubleAttribute;
    success = mkBoolAttribute;
  };

  # DNS-specific attributes
  dnsAttributes = {
    query_name = mkStringAttribute;
    query_type = mkStringAttribute;
    response_code = mkIntAttribute;
    cache_hit = mkBoolAttribute;
    authoritative = mkBoolAttribute;
    recursion_desired = mkBoolAttribute;
  };

  # DHCP-specific attributes
  dhcpAttributes = {
    client_mac = mkStringAttribute;
    client_ip = mkStringAttribute;
    lease_duration = mkIntAttribute;
    reservation_type = mkStringAttribute;
    ddns_update = mkBoolAttribute;
  };

  # Network-specific attributes
  networkAttributes = {
    src_ip = mkStringAttribute;
    dst_ip = mkStringAttribute;
    src_port = mkIntAttribute;
    dst_port = mkIntAttribute;
    protocol = mkStringAttribute;
    packet_size = mkIntAttribute;
    ttl = mkIntAttribute;
    tos = mkIntAttribute;
  };

  # Sampling utilities
  shouldSample = {
    strategy,
    probability ? 0.1,
    serviceOverrides ? {},
    serviceName ? null
  }: let
    effectiveProbability = if serviceName != null && builtins.hasAttr serviceName serviceOverrides
                           then serviceOverrides.${serviceName}
                           else probability;
  in
    if strategy == "always" then true
    else if strategy == "never" then false
    else if strategy == "probabilistic" then
      let
        rand = lib.mod (builtins.currentTime * 1000) 1000;
        threshold = effectiveProbability * 1000;
      in rand < threshold
    else true;

  # Trace correlation helpers
  injectTraceContext = {
    traceId,
    spanId,
    headers ? {}
  }: headers // {
    "x-trace-id" = traceId;
    "x-span-id" = spanId;
  };

  extractTraceContext = headers: {
    traceId = headers."x-trace-id" or null;
    spanId = headers."x-span-id" or null;
    parentSpanId = headers."x-parent-span-id" or null;
  };

  # Performance analysis helpers
  analyzeSpanPerformance = span: let
    duration = span.duration or 0;
    attributes = span.attributes or {};
  in {
    inherit duration;
    isSlow = duration > 1000; # 1 second
    hasErrors = span.status != "ok";
    resourceUsage = attributes.cpu_usage or attributes.memory_usage or null;
  };

  # Dependency mapping
  buildDependencyGraph = spans: let
    # Group spans by trace
    traces = lib.groupBy (span: span.traceId) spans;

    # Build dependency relationships
    dependencies = lib.mapAttrs (traceId: traceSpans: let
      sortedSpans = lib.sort (a: b: a.startTime < b.startTime) traceSpans;
      deps = lib.zipLists (lib.init sortedSpans) (lib.tail sortedSpans);
    in lib.listToAttrs (map (dep: {
      name = "${dep.fst.serviceName} -> ${dep.snd.serviceName}";
      value = {
        from = dep.fst.serviceName;
        to = dep.snd.serviceName;
        latency = dep.snd.startTime - dep.fst.endTime;
      };
    }) deps)) traces;
  in dependencies;

  # Anomaly detection
  detectAnomalies = {
    spans,
    baseline ? {},
    threshold ? 2.0
  }: let
    # Calculate statistics
    durations = map (span: span.duration or 0) spans;
    avgDuration = lib.foldl (acc: x: acc + x) 0 durations / lib.length durations;
    stdDev = lib.sqrt (lib.foldl (acc: x: acc + x) 0 durations / lib.length durations);

    # Find anomalies
    anomalies = lib.filter (span: let
      duration = span.duration or 0;
      zscore = if stdDev == 0 then 0 else (duration - avgDuration) / stdDev;
    in lib.abs zscore > threshold) spans;
  in {
    inherit anomalies avgDuration stdDev;
    anomalyCount = lib.length anomalies;
  };

  # Report generation
  generateTraceReport = {
    spans,
    timeRange,
    serviceFilter ? null
  }: let
    filteredSpans = if serviceFilter == null then spans
                    else lib.filter (span: span.serviceName == serviceFilter) spans;

    stats = {
      totalSpans = lib.length filteredSpans;
      uniqueTraces = lib.length (lib.unique (map (span: span.traceId) filteredSpans));
      services = lib.unique (map (span: span.serviceName) filteredSpans);
      avgDuration = let
        durations = map (span: span.duration or 0) filteredSpans;
      in if durations == [] then 0 else lib.foldl (acc: x: acc + x) 0 durations / lib.length durations;
    };

    anomalies = detectAnomalies { inherit spans; };
  in {
    inherit stats anomalies timeRange serviceFilter;
    spans = filteredSpans;
    generatedAt = builtins.currentTime;
  };
}
