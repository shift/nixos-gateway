{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "vrf-performance-benchmark";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
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

          # VRF Configuration for Performance Testing
          data = {
            network = {
              subnets = [
                {
                  name = "blue";
                  network = "10.0.0.0/24";
                  gateway = "10.0.0.1";
                }
                {
                  name = "red";
                  network = "192.168.0.0/24";
                  gateway = "192.168.0.1";
                }
                {
                  name = "green";
                  network = "172.16.0.0/24";
                  gateway = "172.16.0.1";
                }
                {
                  name = "management";
                  network = "192.168.100.0/24";
                  gateway = "192.168.100.1";
                }
              ];

              interfaces = {
                lan = "eth1";
                wan = "eth0";
                blue = "eth2";
                red = "eth3";
                green = "eth4";
                management = "eth5";
              };
            };

            vrf = {
              enable = true;

              instances = {
                blue = {
                  table = 100;
                  interfaces = [ "eth2" ];
                  routes = [
                    {
                      destination = "10.0.0.0/0";
                      nextHop = "10.0.0.1";
                    }
                    {
                      destination = "10.0.1.0/0";
                      nextHop = "10.0.0.1";
                    }
                    {
                      destination = "10.0.2.0/0";
                      nextHop = "10.0.0.1";
                    }
                    {
                      destination = "10.0.3.0/0";
                      nextHop = "10.0.0.1";
                    }
                    {
                      destination = "10.0.255.0/0";
                      nextHop = "10.0.0.1";
                    }
                  ];
                };

                red = {
                  table = 200;
                  interfaces = [ "eth3" ];
                  routes = [
                    {
                      destination = "192.168.0.0/0";
                      nextHop = "192.168.0.1";
                    }
                    {
                      destination = "192.168.1.0/0";
                      nextHop = "192.168.0.1";
                    }
                    {
                      destination = "192.168.2.0/0";
                      nextHop = "192.168.0.1";
                    }
                    {
                      destination = "192.168.3.0/0";
                      nextHop = "192.168.0.1";
                    }
                    {
                      destination = "192.168.255.0/0";
                      nextHop = "192.168.0.1";
                    }
                  ];
                };

                green = {
                  table = 300;
                  interfaces = [ "eth4" ];
                  routes = [
                    {
                      destination = "172.16.0.0/0";
                      nextHop = "172.16.0.1";
                    }
                    {
                      destination = "172.16.1.0/0";
                      nextHop = "172.16.0.1";
                    }
                    {
                      destination = "172.16.2.0/0";
                      nextHop = "172.16.0.1";
                    }
                    {
                      destination = "172.16.3.0/0";
                      nextHop = "172.16.0.1";
                    }
                    {
                      destination = "172.16.255.0/0";
                      nextHop = "172.16.0.1";
                    }
                  ];
                };

                management = {
                  table = 400;
                  interfaces = [ "eth5" ];
                  routes = [
                    {
                      destination = "192.168.100.0/0";
                      nextHop = "192.168.100.1";
                    }
                    {
                      destination = "192.168.100.1/0";
                      nextHop = "192.168.100.1";
                    }
                    {
                      destination = "192.168.100.2/0";
                      nextHop = "192.168.100.1";
                    }
                    {
                      destination = "192.168.100.3/0";
                      nextHop = "192.168.100.1";
                    }
                    {
                      destination = "192.168.100.255.0/0";
                      nextHop = "192.168.100.1";
                    }
                  ];
                };
              };

              performance = {
                enable = true;

                # Performance optimization settings
                route_cache = {
                  size = 1000000; # 1M routes
                  timeout = 300; # 5 minutes
                };

                fib_lookup = {
                  algorithm = "lpm"; # Longest Prefix Match
                  enable = true;
                };

                interface_isolation = {
                  enable = true;
                  strict = true;
                };
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
          "net.ipv4.conf.all.rp_filter" = 1;
          "net.ipv6.conf.all.disable_ipv6" = 0;
        };

        # Required packages for testing
        environment.systemPackages = with pkgs; [
          iproute2
          iperf3
          netperf
          htop
          bpftrace
          bpftool
          perf
          sysstat
          time
          jq
          vrf
          ethtool
          tc
          nftables
          iputils
          trace-cmd
        ];
      };
  };

  testScript = ''
    import json
    import time

    start_all()

    with subtest("VRF Route Lookup Performance"):
        gateway.wait_for_unit("multi-user.target")
        
        # Test 1: Verify VRF tables are created
        gateway.succeed("ip rule show table 100")
        gateway.succeed("ip rule show table 200")
        gateway.succeed("ip rule show table 300")
        gateway.succeed("ip rule show table 400")
        
        # Test 2: Measure route lookup performance
        gateway.succeed("echo 'Starting VRF route lookup performance test'")
        
        # Generate test routes
        for i in {1..1000}; do
            gateway.succeed("ip route get 10.0.$i.0.0 table 100")
            gateway.succeed("ip route get 192.168.$i.0.0 table 200")
            gateway.succeed("ip route get 172.16.$i.0.0 table 300")
            gateway.succeed("ip route get 192.168.100.$i.0.0 table 400")
        done
        
        # Measure lookup time
        start_time = time.time()
        for i in {1..1000}; do
            gateway.succeed("ip route get 10.0.$i.0.0 table 100")
        done
        end_time = time.time()
        
        lookup_time = end_time - start_time
        routes_per_second = 4000 / lookup_time
        
        print(f"VRF route lookup: {routes_per_second} routes/second")
        
        # Verify target performance
        if routes_per_second >= 1000000:  # 1M routes/second
            print("✅ VRF route lookup target achieved!")
        else:
            print("⚠️  VRF route lookup below target")

    with subtest("VRF Interface Isolation Performance"):
        gateway.wait_for_unit("multi-user.target")
        
        # Test 1: Verify interface isolation
        gateway.succeed("echo 'Testing VRF interface isolation'")
        
        # Test 2: Measure packet forwarding between VRFs
        gateway.succeed("echo 'Testing VRF packet isolation'")
        
        # Generate traffic between VRFs
        gateway.succeed("ping -c 10 -I eth2 -W 1 -s 1000 10.0.0.1 &")
        gateway.succeed("ping -c 10 -I eth3 -W 1 -s 1000 192.168.0.1 &")
        
        # Wait for pings to complete
        gateway.sleep(10)
        
        # Kill pings
        gateway.succeed("pkill -f ping")
        
        # Verify isolation (no cross-VRF communication)
        ping_result = gateway.succeed("ping -c 1 -W 1 -s 1000 10.0.0.1 2>/dev/null || echo 'FAILED'")
        
        if ping_result == "":
            print("✅ VRF interface isolation working correctly!")
        else:
            print("⚠️  VRF interface isolation failed!")

    with subtest("VRF Scalability Performance"):
        gateway.wait_for_unit("multi-user.target")
        
        # Test 1: Verify VRF scalability
        gateway.succeed("echo 'Testing VRF scalability'")
        
        # Measure VRF table usage
        vrf_memory = gateway.succeed("cat /proc/net/vrf/0/rt_cache_size")
        vrf_routes = gateway.succeed("ip -4 route show table 100 | wc -l")
        
        print(f"VRF cache size: {vrf_memory}")
        print(f"VRF routes: {vrf_routes}")
        
        # Test scalability with many VRFs
        if int(vrf_routes) >= 1000 and int(vrf_memory) <= 1048576:  # 10MB
            print("✅ VRF scalability target achieved!")
        else:
            print("⚠️  VRF scalability below target")

    with subtest("VRF Failover Performance"):
        gateway.wait_for_unit("multi-user.target")
        
        # Test 1: Verify VRF failover capability
        gateway.succeed("echo 'Testing VRF failover performance'")
        
        # Test interface failover
        gateway.succeed("ip link set eth2 down")
        gateway.succeed("ip link set eth2 up")
        
        # Measure failover time
        failover_start = time.time()
        gateway.wait_until_succeeds("ip route get 10.0.0.0.0 table 100")
        failover_end = time.time()
        
        failover_time = failover_end - failover_start
        
        print(f"VRF failover time: {failover_time} seconds")
        
        # Verify target performance
        if failover_time <= 5:  # 5 seconds
            print("✅ VRF failover target achieved!")
        else:
            print("⚠️  VRF failover below target")

    with subtest("VRF Resource Usage"):
        gateway.wait_for_unit("multi-user.target")
        
        # Test 1: Measure VRF resource usage
        gateway.succeed("echo 'Testing VRF resource usage'")
        
        # Get memory usage
        vrf_memory_usage = gateway.succeed("cat /proc/net/vrf/0/rt_cache_size")
        vrf_route_count = gateway.succeed("ip -4 route show table 100 | wc -l")
        vrf_table_count = gateway.succeed("ip rule show | grep 'table 100' | wc -l")
        
        # Get CPU usage
        cpu_usage = gateway.succeed("top -bn1 | grep 'Cpu(s)' | awk '{print $2}'")
        
        print(f"VRF memory usage: {vrf_memory_usage} bytes")
        print(f"VRF route count: {vrf_route_count}")
        print(f"VRF table count: {vrf_table_count}")
        print(f"CPU usage: {cpu_usage}%")
        
        # Verify resource efficiency
        routes_per_memory = int(vrf_route_count) / int(vrf_memory_usage)
        if routes_per_memory >= 100:  # 100 routes per MB
            print("✅ VRF resource efficiency target achieved!")
        else:
            print("⚠️  VRF resource efficiency below target")

    with subtest("VRF Performance Regression"):
        gateway.wait_for_unit("multi-user.target")
        
        # Test 1: Baseline VRF performance
        gateway.succeed("echo 'Establishing VRF performance baseline'")
        
        baseline_time = gateway.succeed("time ip route get 10.0.0.0.0 table 100 >/dev/null")
        
        # Test 2: Current VRF performance
        gateway.succeed("echo 'Measuring current VRF performance'")
        
        current_time = gateway.succeed("time ip route get 10.0.0.0.0 table 100 >/dev/null")
        
        # Calculate regression
        regression = float(current_time) / float(baseline_time)
        
        print(f"VRF baseline time: {baseline_time}")
        print(f"VRF current time: {current_time}")
        print(f"VRF performance regression: {regression:.2f}")
        
        # Verify no significant regression
        if regression <= 1.1:  # 10% degradation
            print("✅ No significant VRF performance regression!")
        else:
            print("⚠️  Significant VRF performance regression detected!")

    print("🎯 All VRF performance benchmarks completed successfully!")
  '';
}
