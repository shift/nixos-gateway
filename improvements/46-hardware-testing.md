# Hardware Testing

**Status: Pending**

## Description
Implement hardware-specific testing to validate gateway functionality on different hardware platforms.

## Requirements

### Current State
- Software-only testing
- No hardware validation
- Limited platform coverage

### Improvements Needed

#### 1. Hardware Testing Framework
- Multi-platform testing
- Hardware-specific validation
- Performance benchmarking
- Compatibility testing

#### 2. Platform Coverage
- x86_64 testing
- ARM64 testing
- Different NIC vendors
- Various storage types

#### 3. Hardware Validation
- Driver compatibility
- Hardware acceleration
- Resource utilization
- Performance optimization

#### 4. Automation and Reporting
- Automated hardware detection
- Platform-specific test suites
- Performance comparison
- Hardware recommendation

## Implementation Details

### Files to Create
- `tests/hardware-testing.nix` - Hardware testing framework
- `lib/hardware-validator.nix` - Hardware validation utilities

### Hardware Testing Configuration
```nix
services.gateway.hardwareTesting = {
  enable = true;
  
  platforms = [
    {
      name: "x86_64-intel";
      description: "Intel x86_64 platform";
      architecture = "x86_64";
      cpuVendor = "Intel";
      
      testSuites = [
        "basic-functionality"
        "performance-benchmarks"
        "network-performance"
        "hardware-acceleration"
      ];
      
      hardware = {
        cpu = {
          features = [ "aes" "avx2" "sse4_2" ];
          minCores = 2;
          minFrequency = "2GHz";
        };
        
        network = {
          vendors = [ "Intel" "Broadcom" "Realtek" ];
          features = [ "rss" "tso" "gso" ];
        };
        
        storage = {
          types = [ "ssd" "nvme" ];
          minSpeed = "500MB/s";
        };
      };
    }
    {
      name: "x86_64-amd";
      description: "AMD x86_64 platform";
      architecture = "x86_64";
      cpuVendor = "AMD";
      
      testSuites = [
        "basic-functionality"
        "performance-benchmarks"
        "network-performance"
        "hardware-acceleration"
      ];
      
      hardware = {
        cpu = {
          features = [ "aes" "avx2" "sse4_2" ];
          minCores = 2;
          minFrequency = "2GHz";
        };
        
        network = {
          vendors = [ "AMD" "Intel" "Realtek" ];
          features = [ "rss" "tso" "gso" ];
        };
        
        storage = {
          types = [ "ssd" "nvme" ];
          minSpeed = "500MB/s";
        };
      };
    }
    {
      name: "aarch64";
      description: "ARM64 platform";
      architecture = "aarch64";
      cpuVendor = "ARM";
      
      testSuites = [
        "basic-functionality"
        "performance-benchmarks"
        "network-performance"
        "power-efficiency"
      ];
      
      hardware = {
        cpu = {
          features = [ "aes" "sha1" "sha2" ];
          minCores = 4;
          minFrequency = "1.5GHz";
        };
        
        network = {
          vendors = [ "Broadcom" "Realtek" ];
          features = [ "rss" "tso" ];
        };
        
        storage = {
          types = [ "emmc" "ssd" ];
          minSpeed = "200MB/s";
        };
      };
    }
  ];
  
  testSuites = {
    basicFunctionality = {
      description: "Basic gateway functionality tests";
      duration: "30m";
      
      tests = [
        {
          name: "service-startup";
          description: "Test all services start correctly";
          validation = {
            type: "service-status";
            services: [ "knot" "kea-dhcp4-server" "suricata" ];
            expected: "active";
          };
        }
        {
          name: "network-interfaces";
          description: "Test network interfaces are configured";
          validation = {
            type: "interface-check";
            interfaces: [ "wan" "lan" ];
            expected: "up";
          };
        }
        {
          name: "basic-connectivity";
          description: "Test basic network connectivity";
          validation = {
            type: "connectivity-test";
            targets: [ "8.8.8.8" "1.1.1.1" ];
            expected: "reachable";
          };
        }
      ];
    };
    
    performanceBenchmarks = {
      description: "Performance benchmarking tests";
      duration: "60m";
      
      benchmarks = [
        {
          name: "cpu-performance";
          description: "CPU performance benchmark";
          tool: "sysbench";
          parameters = {
            test: "cpu";
            threads: "auto";
            time: "60";
          };
          metrics = [ "events-per-second" "latency" ];
        }
        {
          name: "memory-performance";
          description: "Memory performance benchmark";
          tool: "sysbench";
          parameters = {
            test: "memory";
            threads: "auto";
            time: "60";
          };
          metrics = [ "bandwidth" "latency" ];
        }
        {
          name: "network-throughput";
          description: "Network throughput benchmark";
          tool: "iperf3";
          parameters = {
            duration: "60";
            parallel: 4;
            windowSize: "1M";
          };
          metrics = [ "throughput" "jitter" "packet-loss" ];
        }
        {
          name: "disk-io";
          description: "Disk I/O benchmark";
          tool: "fio";
          parameters = {
            test: "randread";
            size: "1G";
            blockSize: "4k";
          };
          metrics = [ "iops" "bandwidth" "latency" ];
        }
      ];
    };
    
    networkPerformance = {
      description: "Network performance specific tests";
      duration: "45m";
      
      tests = [
        {
          name: "packet-processing";
          description: "Test packet processing capabilities";
          tool: "custom";
          parameters = {
            packetRate: 1000000;
            duration: "300";
            packetSize: 1500;
          };
          metrics = [ "packets-per-second" "cpu-usage" "drop-rate" ];
        }
        {
          name: "connection-tracking";
          description: "Test connection tracking performance";
          tool: "conntrack";
          parameters = {
            connections: 100000;
            duration: "300";
          };
          metrics = [ "tracking-rate" "memory-usage" "table-size" ];
        }
        {
          name: "hardware-offload";
          description: "Test hardware offload features";
          tool: "ethtool";
          parameters = {
            features: [ "tso" "gso" "gro" "lro" ];
          };
          metrics = [ "offload-status" "performance-impact" ];
        }
      ];
    };
    
    hardwareAcceleration = {
      description: "Hardware acceleration tests";
      duration: "30m";
      
      tests = [
        {
          name: "crypto-acceleration";
          description: "Test cryptographic acceleration";
          tool: "openssl";
          parameters = {
            algorithm: "aes-256-cbc";
            operations: 1000000;
          };
          metrics = [ "operations-per-second" "cpu-usage" ];
        }
        {
          name: "checksum-offload";
          description: "Test checksum offload";
          tool: "ethtool";
          parameters = {
            feature: "rx-checksum";
          };
          metrics = [ "offload-status" "performance-gain" ];
        }
        {
          name: "vector-processing";
          description: "Test SIMD vector processing";
          tool: "custom";
          parameters = {
            instructionSet: "avx2";
            operations: 1000000;
          };
          metrics = [ "operations-per-second" "efficiency" ];
        }
      ];
    };
    
    powerEfficiency = {
      description: "Power efficiency tests (ARM specific)";
      duration: "60m";
      
      tests = [
        {
          name: "idle-power";
          description: "Measure idle power consumption";
          tool: "power-meter";
          parameters = {
            duration: "300";
            interval: "5";
          };
          metrics = [ "power-watts" "voltage" "current" ];
        }
        {
          name: "load-power";
          description: "Measure power under load";
          tool: "power-meter";
          parameters = {
            load: "cpu-stress";
            duration: "600";
            interval: "5";
          };
          metrics = [ "power-watts" "efficiency" ];
        }
        {
          name: "performance-per-watt";
          description: "Calculate performance per watt";
          calculation: "performance-metrics / power-consumption";
          metrics = [ "performance-per-watt" "efficiency-rating" ];
        }
      ];
    };
  };
  
  automation = {
    detection = {
      enable = true;
      
      hardware = {
        cpu = {
          vendor = "/proc/cpuinfo";
          features = "/proc/cpuinfo";
          cores = "nproc";
          frequency = "/proc/cpuinfo";
        };
        
        network = {
          interfaces = "ip link";
          drivers = "ethtool";
          features = "ethtool";
        };
        
        storage = {
          devices = "lsblk";
          types = "lsblk -d -o NAME,ROTA,ROTYPE";
          performance = "hdparm";
        };
      };
      
      platform = {
        architecture = "uname -m";
        kernel = "uname -r";
        distribution = "cat /etc/os-release";
      };
    };
    
    selection = {
      enable = true;
      
      criteria = [
        {
          name: "cpu-vendor";
          type: "match";
          field: "cpu.vendor";
          values: [ "Intel" "AMD" "ARM" ];
        }
        {
          name: "architecture";
          type: "match";
          field: "platform.architecture";
          values: [ "x86_64" "aarch64" ];
        }
        {
          name: "network-vendor";
          type: "match";
          field: "network.driver";
          values: [ "Intel" "Broadcom" "Realtek" ];
        }
      ];
      
      testSuites = {
        "x86_64-intel" = [ "basic-functionality" "performance-benchmarks" "network-performance" "hardware-acceleration" ];
        "x86_64-amd" = [ "basic-functionality" "performance-benchmarks" "network-performance" "hardware-acceleration" ];
        "aarch64" = [ "basic-functionality" "performance-benchmarks" "network-performance" "power-efficiency" ];
      };
    };
  };
  
  reporting = {
    results = {
      storage = {
        type = "database";
        path = "/var/lib/hardware-test-results";
        
        schema = {
          platform: "string";
          testSuite: "string";
          testName: "string";
          result: "string";
          metrics: "json";
          timestamp: "datetime";
        };
      };
      
      retention = {
        duration = "365d";
        maxRecords = 10000;
      };
    };
    
    comparison = {
      enable = true;
      
      baseline = {
        type: "reference";
        source: "manufacturer-specs";
      };
      
      analysis = {
        enable = true;
        
        metrics = [
          "performance-ratio"
          "efficiency-rating"
          "compatibility-score"
          "stability-rating"
        ];
      };
    };
    
    dashboards = {
      enable = true;
      
      panels = [
        {
          title: "Hardware Overview";
          type: "summary";
          metrics: [ "platform" "cpu" "memory" "network" ];
        }
        {
          title: "Performance Comparison";
          type: "chart";
          metrics: [ "cpu-performance" "memory-performance" "network-performance" ];
        }
        {
          title: "Hardware Acceleration";
          type: "status";
          metrics: [ "crypto-acceleration" "checksum-offload" "vector-processing" ];
        }
        {
          title: "Power Efficiency";
          type: "gauge";
          metrics: [ "power-consumption" "performance-per-watt" ];
        }
      ];
    };
  };
  
  integration = {
    ci = {
      enable = true;
      
      runners = [
        {
          name: "x86_64-runner";
          tags = [ "x86_64" "intel" ];
          resources = {
            cpu: 4;
            memory: "8GB";
          };
        }
        {
          name: "aarch64-runner";
          tags = [ "aarch64" "arm" ];
          resources = {
            cpu: 4;
            memory: "8GB";
          };
        }
      ];
      
      scheduling = {
        enable = true;
        
        triggers = [
          {
            name: "on-commit";
            condition: "git.push";
            platforms: [ "all" ];
          }
          {
            name: "weekly";
            condition: "cron.weekly";
            platforms: [ "all" ];
          }
          {
            name: "release";
            condition: "git.tag";
            platforms: [ "all" ];
          }
        ];
      };
    };
    
    monitoring = {
      enable = true;
      
      metrics = [
        "test-duration"
        "test-success-rate"
        "hardware-compatibility"
        "performance-baseline"
      ];
      
      alerts = [
        {
          name: "hardware-failure";
          condition: "test.status = failed";
          severity: "high";
        }
        {
          name: "performance-degradation";
          condition: "performance.ratio < 0.8";
          severity: "medium";
        }
      ];
    };
  };
};
```

### Integration Points
- CI/CD systems
- Hardware detection tools
- Performance monitoring
- Test result storage

## Testing Requirements
- Hardware detection accuracy
- Test suite completeness
- Performance measurement accuracy
- Platform compatibility validation

## Dependencies
- 41-performance-regression-tests
- 42-failure-scenario-testing

## Estimated Effort
- High (complex hardware testing)
- 6 weeks implementation
- 4 weeks testing

## Success Criteria
- Comprehensive platform coverage
- Accurate hardware detection
- Reliable performance measurement
- Good hardware compatibility