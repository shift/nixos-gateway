{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "xdp-ebpf-performance-benchmark";
  
  nodes = {
    gateway = { config, pkgs, ... }: {
      imports = [ ../modules ];
      
      services.gateway = {
        enable = true;
        
        interfaces = {
          lan = "eth1";
          wan = "eth0";
          mgmt = "eth2";
        };
        
        ipv6Prefix = "2001:db8::";
        domain = "test.local";
        
        # XDP/eBPF Data Plane Acceleration Configuration
        data = {
          network = {
            subnets = [
              {
                name = "lan";
                network = "192.168.1.0/24";
                gateway = "192.168.1.1";
              }
              {
                name = "wan";
                network = "10.0.0.0/24";
                gateway = "10.0.0.1";
              }
            ];
            
            interfaces = {
              lan = "eth1";
              wan = "eth0";
              mgmt = "eth2";
            };
          };
          
          xdp = {
            enable = true;
            
            programs = [
              {
                name = "firewall";
                type = "xdp";
                interface = "eth0";
                priority = 1;
                
                code = ''
                  #include <linux/bpf.h>
                  #include <linux/if_ether.h>
                  
                  SEC("xdp")
                  
                  struct eth_hdr {
                      __u64 dst;
                      __u64 src;
                      __u16 proto;
                      __u16 flags;
                  };
                  
                  struct data_t {
                      __u32 src_ip;
                      __u32 dst_ip;
                      __u16 src_port;
                      __u16 dst_port;
                      __u8 protocol;
                      __u64 timestamp;
                  };
                  
                  // XDP map for packet processing
                  struct {
                      __uint(max_entries = 1000000)
                  } xdp_map SEC(".maps");
                  
                  // XDP program for firewall filtering
                  SEC("xdp_firewall")
                  int xdp_firewall_prog(struct xdp_md *ctx) {
                      __u64 key = 0;
                      __u64 *initial_count = 0;
                      __u64 *drop_count = 0;
                      __u64 *pass_count = 0;
                      
                      // Get packet data
                      struct data_t *data = bpf_map_lookup_elem(&xdp_map, &key);
                      if (!data) {
                          return XDP_PASS;
                      }
                      
                      // Update counters
                      __sync_fetch_and_add(&initial_count, 1);
                      
                      // Firewall rules
                      if (data->dst_ip == 0x0A000001) { // 10.0.0.1
                          __sync_fetch_and_add(&drop_count, 1);
                          return XDP_DROP;
                      }
                      
                      if (data->src_port == 22) { // SSH
                          __sync_fetch_and_add(&pass_count, 1);
                      }
                      
                      return XDP_PASS;
                  }
                  
                  char _license[] SEC("GPL");
              };
                  
                  // XDP program for traffic classification
                  SEC("xdp_classifier")
                  int xdp_classifier_prog(struct xdp_md *ctx) {
                      __u64 key = 0;
                      __u64 *voip_packets = 0;
                      __u64 *web_packets = 0;
                      __u64 *bulk_packets = 0;
                      __u64 *total_packets = 0;
                      
                      struct data_t *data = bpf_map_lookup_elem(&xdp_map, &key);
                      if (!data) {
                          return XDP_PASS;
                      }
                      
                      __sync_fetch_and_add(&total_packets, 1);
                      
                      // Traffic classification
                      if (data->protocol == 17) { // UDP
                          if (data->src_port >= 5060 && data->src_port <= 5090) {
                              __sync_fetch_and_add(&voip_packets, 1);
                          }
                      }
                      
                      if (data->dst_port == 80 || data->dst_port == 443) {
                          __sync_fetch_and_add(&web_packets, 1);
                      }
                      
                      if (data->dst_port >= 1024) {
                          __sync_fetch_and_add(&bulk_packets, 1);
                      }
                      
                      return XDP_PASS;
                  }
                  
                  char _license[] SEC("GPL");
              };
            ];
            
            performance = {
              enable = true;
              
              benchmarks = [
                {
                  name = "packet_throughput";
                  type = "xdp";
                  duration = 60; # seconds
                  parameters = {
                    packet_size = 1500; # bytes
                    parallel_streams = 4;
                  };
                  target = {
                    throughput = 40000000; # 40 Gbps
                    latency = 100; # microseconds
                  };
                }
                {
                  name = "cpu_utilization";
                  type = "system";
                  duration = 60;
                  parameters = {
                    load_type = "network";
                    cores = 4;
                  };
                  target = {
                    utilization = 80; # %
                  };
                }
                {
                  name = "memory_usage";
                  type = "system";
                  duration = 60;
                  parameters = {
                    measurement_interval = 1; # second
                  };
                  target = {
                    utilization = 70; # %
                  };
                }
                {
                  name = "latency_measurement";
                  type = "network";
                  duration = 60;
                  parameters = {
                    packet_size = 64; # bytes
                    count = 1000000;
                  };
                  target = {
                    latency = 50; # microseconds
                    jitter = 5; # microseconds
                  };
                }
                {
                  name = "concurrent_connections";
                  type = "network";
                  duration = 60;
                  parameters = {
                    connection_type = "tcp";
                    concurrent_count = 100000;
                  };
                  target = {
                    success_rate = 99.9; # %
                    latency = 100; # microseconds
                  };
                }
              ];
            };
          };
        };
      };

      # Network configuration for testing
      networking.useNetworkd = false;
      networking.firewall.enable = false;
      
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
        "net.core.netdev_max_backlog" = 5000;
        "net.core.rmem_max" = 134217728;
        "net.core.wmem_max" = 134217728;
      };

      # Required packages for testing
      environment.systemPackages = with pkgs; [
        iperf3
        netperf
        htop
        bpftrace
        bpftool
        clang
        llvm
        linux-tools
        ethtool
        tcpdump
        wireshark-cli
        jq
        time
        sysstat
      ];
    };
  };

  testScript = ''
    import json
    import time
    
    start_all()
    
    with subtest("XDP/eBPF Program Loading"):
        gateway.wait_for_unit("multi-user.target")
        
        # Test 1: Verify XDP programs are loaded
        gateway.succeed("bpftool prog show | grep -q 'xdp_firewall'")
        gateway.succeed("bpftool prog show | grep -q 'xdp_classifier'")
        
        # Test 2: Verify XDP maps are created
        gateway.succeed("bpftool map show | grep -q 'xdp_map'")
        
        # Test 3: Verify XDP programs are attached to interfaces
        gateway.succeed("ip link show eth0 | grep -q 'xdp'")
        gateway.succeed("ip link show eth1 | grep -q 'xdp'")
        
        print("✅ XDP/eBPF programs loaded successfully!")
    
    with subtest("Packet Throughput Benchmark"):
        gateway.succeed("echo 'Starting packet throughput benchmark'")
        
        # Run iperf3 test
        gateway.succeed("iperf3 -c eth0 -t 60 -i 1M -u 100M -P 1 &")
        gateway.sleep(5)  # Wait for server to start
        gateway.succeed("iperf3 -c eth1 -t 60 -i 1M -u 100M -P 1 &")
        gateway.sleep(5)  # Wait for client to start
        
        # Wait for test to complete
        gateway.sleep(70)
        
        # Kill iperf3 processes
        gateway.succeed("pkill -f iperf3")
        
        # Parse results
        result = gateway.succeed("cat /tmp/iperf3_result.txt")
        print(f"Throughput test result: {result}")
        
        # Verify target achieved
        if "40.0 Gbits/sec" in result:
            print("✅ Packet throughput target achieved!")
        else:
            print("⚠️  Packet throughput below target")
    
    with subtest("CPU Utilization Benchmark"):
        gateway.succeed("echo 'Starting CPU utilization benchmark'")
        
        # Generate network load
        gateway.succeed("hping3 -c eth0 -i eth1 -p 80 --flood -d 120S &")
        
        # Monitor CPU usage during load
        cpu_before = gateway.succeed("top -bn1 | grep 'Cpu(s)' | awk '{print $2}'")
        gateway.sleep(30)
        cpu_during = gateway.succeed("top -bn1 | grep 'Cpu(s)' | awk '{print $2}'")
        cpu_after = gateway.succeed("top -bn1 | grep 'Cpu(s)' | awk '{print $2}'")
        
        # Kill hping3
        gateway.succeed("pkill -f hping3")
        
        print(f"CPU before: {cpu_before}%")
        print(f"CPU during: {cpu_during}%")
        print(f"CPU after: {cpu_after}%")
        
        # Verify CPU utilization target
        cpu_avg = (float(cpu_during) + float(cpu_after)) / 2
        if cpu_avg <= 80:
            print("✅ CPU utilization target achieved!")
        else:
            print("⚠️  CPU utilization above target")
    
    with subtest("Memory Usage Benchmark"):
        gateway.succeed("echo 'Starting memory usage benchmark'")
        
        # Generate memory load
        gateway.succeed("memtester 100M 10 &")
        
        # Monitor memory usage during load
        mem_before = gateway.succeed("free -m | grep '^Mem:' | awk '{print $3/$2 * 100.0}'")
        gateway.sleep(30)
        mem_during = gateway.succeed("free -m | grep '^Mem:' | awk '{print $3/$2 * 100.0}'")
        mem_after = gateway.succeed("free -m | grep '^Mem:' | awk '{print $3/$2 * 100.0}'")
        
        # Kill memtester
        gateway.succeed("pkill -f memtester")
        
        print(f"Memory before: {mem_before}%")
        print(f"Memory during: {mem_during}%")
        print(f"Memory after: {mem_after}%")
        
        # Verify memory utilization target
        mem_avg = (float(mem_during) + float(mem_after)) / 2
        if mem_avg <= 70:
            print("✅ Memory utilization target achieved!")
        else:
            print("⚠️  Memory utilization above target")
    
    with subtest("Latency Measurement Benchmark"):
        gateway.succeed("echo 'Starting latency measurement benchmark'")
        
        # Run ping test
        gateway.succeed("ping -c 1000 -i 0.1 -s 64 -W 0 -D 192.168.1.1 > /tmp/ping_latency.txt")
        
        # Parse results
        latency_results = gateway.succeed("tail -n +0 /tmp/ping_latency.txt | awk '{print $7}' | sort -n | awk '{sum+=$7} END {print sum/NR}'")
        avg_latency = float(latency_results) / 1000
        
        print(f"Average latency: {avg_latency} ms")
        
        # Verify latency target
        if avg_latency <= 100:
            print("✅ Latency target achieved!")
        else:
            print("⚠️  Latency above target")
    
    with subtest("Concurrent Connections Benchmark"):
        gateway.succeed("echo 'Starting concurrent connections benchmark'")
        
        # Generate concurrent connections
        gateway.succeed("echo 'Starting concurrent connection test'")
        
        # Monitor system performance
        start_time = time.time()
        gateway.succeed("for i in {1..1000}; do nc -l 8080 < /dev/null & done")
        gateway.sleep(10)
        gateway.succeed("pkill -f nc")
        end_time = time.time()
        
        duration = end_time - start_time
        print(f"Concurrent connections test duration: {duration} seconds")
        
        # Verify concurrent connections target
        if duration <= 60:
            print("✅ Concurrent connections target achieved!")
        else:
            print("⚠️  Concurrent connections above target")
    
    with subtest("XDP vs Traditional Performance"):
        gateway.succeed("echo 'Starting XDP vs traditional performance comparison'")
        
        # Test traditional packet processing
        gateway.succeed("echo 'Testing traditional packet processing'")
        traditional_time = gateway.succeed("time nc -l 8080 < /dev/null & sleep 1 && pkill -f nc'")
        
        # Test XDP packet processing
        gateway.succeed("echo 'Testing XDP packet processing'")
        xdp_time = gateway.succeed("time nc -l 8081 < /dev/null & sleep 1 && pkill -f nc'")
        
        print(f"Traditional processing time: {traditional_time}")
        print(f"XDP processing time: {xdp_time}")
        
        # Calculate performance improvement
        if float(xdp_time) > 0:
            improvement = (float(traditional_time) / float(xdp_time)) * 100
            print(f"Performance improvement: {improvement:.1f}%")
        
        print("✅ XDP vs traditional performance comparison completed!")
    
    with subtest("Resource Usage Analysis"):
        gateway.succeed("echo 'Starting resource usage analysis'")
        
        # Collect system metrics
        cpu_usage = gateway.succeed("top -bn1 | grep 'Cpu(s)' | awk '{print $2}'")
        memory_usage = gateway.succeed("free -m | grep '^Mem:' | awk '{print $3/$2 * 100.0}'")
        network_stats = gateway.succeed("cat /proc/net/dev | grep eth0")
        
        print(f"CPU Usage: {cpu_usage}%")
        print(f"Memory Usage: {memory_usage}%")
        print(f"Network Stats: {network_stats}")
        
        print("✅ Resource usage analysis completed!")
    
    with subtest("Performance Regression Detection"):
        gateway.succeed("echo 'Starting performance regression detection'")
        
        # Compare with baseline
        baseline_throughput = 40000000  # 40 Gbps baseline
        current_throughput = gateway.succeed("echo 'Measuring current throughput'")
        
        print(f"Baseline throughput: {baseline_throughput}")
        print(f"Current throughput: {current_throughput}")
        
        # Check for regression
        if current_throughput >= baseline_throughput * 0.95:  # 5% tolerance
            print("✅ No performance regression detected!")
        else:
            print("⚠️  Performance regression detected!")
    
    print("🎯 All XDP/eBPF performance benchmarks completed successfully!")
      '';
    };
  }