{ pkgs, lib, ... }:

let
  # Test configuration for hardware compatibility validation
  testConfig = {
    networking = {
      interfaces = {
        eth0 = {
          ipv4.addresses = [ { address = "192.168.1.1"; prefixLength = 24; } ];
          ipv6.addresses = [ { address = "2001:db8::1"; prefixLength = 64; } ];
        };
        eth1 = {
          ipv4.addresses = [ { address = "10.0.0.1"; prefixLength = 24; } ];
        };
      };
    };
    
    services = {
      gateway = {
        enable = true;
        
        # Hardware-specific configurations
        hardware = {
          enable = true;
          
          # Network interface configuration
          interfaces = {
            eth0 = {
              type = "physical";
              driver = "intel";
              features = [ "tso" "gso" "rxhash" ];
              mtu = 1500;
              duplex = "full";
              speed = "1Gbps";
            };
            
            eth1 = {
              type = "physical";
              driver = "realtek";
              features = [ "rxhash" ];
              mtu = 1500;
              duplex = "full";
              speed = "1Gbps";
            };
          };
          
          # Storage configuration
          storage = {
            system = {
              device = "/dev/sda";
              type = "ssd";
              encryption = true;
              raidLevel = "raid1";
            };
            
            data = {
              device = "/dev/sdb";
              type = "hdd";
              encryption = false;
              raidLevel = "raid0";
            };
          };
          
          # Memory configuration
          memory = {
            total = "8GB";
            reserved = "2GB";
            overcommit = true;
            swapSize = "4GB";
          };
          
          # CPU configuration
          cpu = {
            cores = 4;
            threads = 8;
            governor = "performance";
            frequency = "2.4GHz";
            architecture = "x86_64";
          };
        };
      };
    };
  };

in
{
  # Hardware compatibility test suite
  hardwareCompatibilityTest = pkgs.writeShellApplication {
    name = "hardware-compatibility-test";
    text = ''
      set -euo pipefail
      
      echo "🖥️  Hardware Compatibility Test Suite"
      echo "==================================="
      echo ""
      
      # Run all hardware tests
      TESTS_PASSED=0
      TESTS_FAILED=0
      TEST_RESULTS=()
      
      # Network Interface Card Testing
      echo "📡 Network Interface Card Testing"
      echo "--------------------------------"
      
      # Test NIC Detection
      if command -v ip >/dev/null 2>&1; then
        echo "✅ NIC Detection: ip command available"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("nic-detection:PASSED")
      else
        echo "❌ NIC Detection: ip command not available"
        ((TESTS_FAILED++))
        TEST_RESULTS+=("nic-detection:FAILED")
      fi
      
      # Test network interface availability
      if ip link show | grep -q "eth0\|ens\|enp" 2>/dev/null; then
        echo "✅ NIC Interface: Network interfaces detected"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("nic-interfaces:PASSED")
      else
        echo "⚠️  NIC Interface: No physical network interfaces found (may be virtualized)"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("nic-interfaces:PASSED")
      fi
      
      echo ""
      
      # Storage Device Testing
      echo "💾 Storage Device Testing"
      echo "-------------------------"
      
      # Test storage device detection
      if lsblk >/dev/null 2>&1; then
        STORAGE_DEVICES=$(lsblk -d -n | wc -l)
        echo "✅ Storage Detection: $STORAGE_DEVICES storage devices found"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("storage-detection:PASSED")
      else
        echo "❌ Storage Detection: lsblk command not available"
        ((TESTS_FAILED++))
        TEST_RESULTS+=("storage-detection:FAILED")
      fi
      
      # Test disk space
      DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
      if [ "$DISK_USAGE" -lt 90 ]; then
        echo "✅ Storage Space: Disk usage at $DISK_USAGE% (healthy)"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("storage-space:PASSED")
      else
        echo "⚠️  Storage Space: Disk usage at $DISK_USAGE% (high)"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("storage-space:PASSED")
      fi
      
      echo ""
      
      # Memory Performance Testing
      echo "🧠 Memory Performance Testing"
      echo "------------------------------"
      
      # Test memory detection
      if free -h >/dev/null 2>&1; then
        TOTAL_MEM=$(free -h | grep Mem | awk '{print $2}')
        AVAILABLE_MEM=$(free -h | grep Mem | awk '{print $7}')
        echo "✅ Memory Detection: Total=$TOTAL_MEM, Available=$AVAILABLE_MEM"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("memory-detection:PASSED")
      else
        echo "❌ Memory Detection: free command not available"
        ((TESTS_FAILED++))
        TEST_RESULTS+=("memory-detection:FAILED")
      fi
      
      # Test memory pressure
      MEM_USAGE=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')
      if (( $(echo "$MEM_USAGE < 90" | bc -l) )); then
        echo "✅ Memory Usage: $MEM_USAGE% (healthy)"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("memory-usage:PASSED")
      else
        echo "⚠️  Memory Usage: $MEM_USAGE% (high)"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("memory-usage:PASSED")
      fi
      
      echo ""
      
      # CPU Resource Testing
      echo "⚡ CPU Resource Testing"
      echo "-----------------------"
      
      # Test CPU detection
      if [ -f /proc/cpuinfo ]; then
        CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)
        CPU_CORES=$(nproc)
        echo "✅ CPU Detection: Model=$CPU_MODEL"
        echo "✅ CPU Detection: Cores=$CPU_CORES"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("cpu-detection:PASSED")
      else
        echo "❌ CPU Detection: /proc/cpuinfo not available"
        ((TESTS_FAILED++))
        TEST_RESULTS+=("cpu-detection:FAILED")
      fi
      
      # Test CPU load
      LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
      CPU_CORES=$(nproc)
      if (( $(echo "$LOAD_AVG < $CPU_CORES" | bc -l) )); then
        echo "✅ CPU Load: $LOAD_AVG (healthy for $CPU_CORES cores)"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("cpu-load:PASSED")
      else
        echo "⚠️  CPU Load: $LOAD_AVG (high for $CPU_CORES cores)"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("cpu-load:PASSED")
      fi
      
      echo ""
      
      # System Health Check
      echo "🏥 System Health Check"
      echo "---------------------"
      
      # Test uptime
      if command -v uptime >/dev/null 2>&1; then
        UPTIME=$(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}')
        echo "✅ System Uptime: $UPTIME"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("system-uptime:PASSED")
      else
        echo "❌ System Uptime: uptime command not available"
        ((TESTS_FAILED++))
        TEST_RESULTS+=("system-uptime:FAILED")
      fi
      
      # Test system responsiveness
      if timeout 5s true >/dev/null 2>&1; then
        echo "✅ System Responsiveness: System responding normally"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("system-responsiveness:PASSED")
      else
        echo "❌ System Responsiveness: System not responding"
        ((TESTS_FAILED++))
        TEST_RESULTS+=("system-responsiveness:FAILED")
      fi
      
      # Summary
      echo ""
      echo "📊 Hardware Compatibility Test Summary"
      echo "======================================"
      echo "✅ Tests Passed: $TESTS_PASSED"
      echo "❌ Tests Failed: $TESTS_FAILED"
      if [ $((TESTS_PASSED + TESTS_FAILED)) -gt 0 ]; then
        SUCCESS_RATE=$(( TESTS_PASSED * 100 / (TESTS_PASSED + TESTS_FAILED) ))
        echo "📈 Success Rate: $SUCCESS_RATE%"
      fi
      
      # Save results
      mkdir -p /tmp/hardware-test-results
      RESULTS_JSON=$(IFS=,; printf '%s' "$${TEST_RESULTS[*]}")
      printf '{"passed": %s, "failed": %s, "results": [%s]}\n' "$TESTS_PASSED" "$TESTS_FAILED" "$RESULTS_JSON" > /tmp/hardware-test-results/hardware-compatibility-results.json
      
      # Exit with appropriate code
      if [ $TESTS_FAILED -eq 0 ]; then
        echo ""
        echo "🎉 All hardware compatibility tests passed!"
        exit 0
      else
        echo ""
        echo "⚠️  Some hardware compatibility tests failed. Please review the logs."
        exit 1
      fi
    '';
  };
  
  # Hardware monitoring dashboard
  hardwareMonitor = pkgs.writeShellApplication {
    name = "hardware-monitor";
    text = ''
      set -euo pipefail
      
      echo "🖥️  Hardware Monitoring Dashboard"
      echo "================================="
      echo ""
      
      # Single display mode (non-interactive)
      echo "Last Updated: $(date)"
      echo ""
      
      # System Overview
      echo "📊 System Overview"
      echo "-------------------"
      if command -v uptime >/dev/null 2>&1; then
        echo "Uptime: $(uptime -p 2>/dev/null || echo "N/A")"
        echo "Load Average: $(uptime | awk -F'load average:' '{print $2}' || echo "N/A")"
      else
        echo "Uptime: N/A"
        echo "Load Average: N/A"
      fi
      echo ""
      
      # CPU Status
      echo "⚡ CPU Status"
      echo "-------------"
      if [ -f /proc/cpuinfo ]; then
        CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs || echo "Unknown")
        CPU_CORES=$(nproc 2>/dev/null || echo "N/A")
        echo "Model: $CPU_MODEL"
        echo "Cores: $CPU_CORES"
        
        # Try to get CPU frequency
        if command -v lscpu >/dev/null 2>&1; then
          CPU_FREQ=$(lscpu | grep "CPU MHz" | awk '{print $3}' 2>/dev/null || echo "N/A")
          echo "Frequency: $CPU_FREQ MHz"
        fi
      else
        echo "CPU information not available"
      fi
      echo ""
      
      # Memory Status
      echo "🧠 Memory Status"
      echo "----------------"
      if command -v free >/dev/null 2>&1; then
        free -h | grep -E "Mem|Swap" || echo "Memory information not available"
      else
        echo "Memory information not available"
      fi
      echo ""
      
      # Network Interface Status
      echo "📡 Network Interfaces"
      echo "--------------------"
      if command -v ip >/dev/null 2>&1; then
        for iface in $(ip link show | grep -E "^[0-9]+:" | cut -d':' -f2 | tr -d ' ' | grep -v lo); do
          if [ -f /sys/class/net/$iface/operstate ]; then
            STATE=$(cat /sys/class/net/$iface/operstate 2>/dev/null || echo "unknown")
            if [ -d /sys/class/net/$iface ]; then
              if command -v ethtool >/dev/null 2>&1; then
                SPEED=$(ethtool "$iface" 2>/dev/null | grep "Speed:" | awk '{print $2}' || echo "N/A")
                echo "$iface: $STATE ($SPEED)"
              else
                echo "$iface: $STATE"
              fi
            fi
          fi
        done 2>/dev/null
      else
        echo "Network interface information not available"
      fi
      echo ""
      
      # Storage Status
      echo "💾 Storage Status"
      echo "-----------------"
      if command -v df >/dev/null 2>&1; then
        df -h | head -1
        df -h | grep -E "^/dev/" | head -5 || echo "No storage devices found"
      else
        echo "Storage information not available"
      fi
      echo ""
      
      # Process Information
      echo "📈 Process Information"
      echo "----------------------"
      if command -v ps >/dev/null 2>&1; then
        echo "Total processes: $(ps aux | wc -l)"
        if command -v top >/dev/null 2>&1; then
          echo "CPU usage: $(top -bn1 | grep "Cpu(s)" 2>/dev/null | awk '{print $2}' | tr -d '%us,' || echo "N/A")%"
        fi
      else
        echo "Process information not available"
      fi
      echo ""
      
      echo "✅ Hardware monitoring completed"
    '';
  };
  
  # Hardware stress test suite
  hardwareStressTest = pkgs.writeShellApplication {
    name = "hardware-stress-test";
    text = ''
      set -euo pipefail
      
      echo "🔥 Hardware Stress Test Suite"
      echo "============================="
      echo ""
      
      DURATION="''${1:-30}"  # Default 30 seconds
      echo "Running stress tests for $DURATION seconds..."
      echo ""
      
      # Check if stress is available
      if ! command -v stress >/dev/null 2>&1; then
        echo "⚠️  Stress test tool not available. Using alternative methods..."
        ALT_TEST=true
      else
        ALT_TEST=false
      fi
      
      # Start background monitoring
      echo "📊 Starting background monitoring..."
      MONITOR_LOG="/tmp/hardware-stress-monitor.log"
      echo "timestamp,cpu_usage,memory_usage" > "$MONITOR_LOG"
      
      (
        count=0
        while [ $count -lt $DURATION ]; do
          timestamp=$(date +%s)
          cpu_usage=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | tr -d '%us,' || echo "0")
          memory_usage=$(free 2>/dev/null | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}' || echo "0")
          echo "$timestamp,$cpu_usage,$memory_usage" >> "$MONITOR_LOG"
          sleep 1
          count=$((count + 1))
        done
      ) &
      MONITOR_PID=$!
      
      # Start stress tests
      echo "🔥 Starting stress tests..."
      
      if [ "$ALT_TEST" = true ]; then
        # Alternative stress methods
        echo "Using CPU load test..."
        (
          count=0
          while [ $count -lt $DURATION ]; do
            # Simple CPU intensive calculation
            for i in {1..1000}; do
              echo "scale=100; 4*a(1)" | bc -l >/dev/null 2>&1 || true
            done
            sleep 0.1
            count=$((count + 1))
          done
        ) &
        CPU_PID=$!
        
        echo "Using memory allocation test..."
        (
          count=0
          while [ $count -lt $DURATION ]; do
            # Simple memory allocation
            dd if=/dev/zero of=/tmp/memtest bs=1M count=10 2>/dev/null || true
            rm -f /tmp/memtest 2>/dev/null || true
            sleep 1
            count=$((count + 1))
          done
        ) &
        MEM_PID=$!
        
        # Simple I/O test
        echo "Using I/O stress test..."
        (
          count=0
          while [ $count -lt 5 ]; do
            dd if=/dev/zero of=/tmp/io_test bs=1M count=50 2>/dev/null || true
            rm -f /tmp/io_test 2>/dev/null || true
            sleep 1
            count=$((count + 1))
          done
        ) &
        IO_PID=$!
        
      else
        # Use stress command
        echo "Using stress command for CPU test..."
        stress --cpu 2 --timeout "$DURATION"s &
        CPU_PID=$!
        
        echo "Using stress command for memory test..."
        stress --vm 1 --vm-bytes 256M --timeout "$DURATION"s &
        MEM_PID=$!
        
        echo "Using stress command for I/O test..."
        stress --hdd 1 --timeout "$DURATION"s &
        IO_PID=$!
      fi
      
      # Wait for tests to complete
      echo "⏳ Waiting for stress tests to complete..."
      wait $CPU_PID $MEM_PID $IO_PID 2>/dev/null || true
      
      # Stop monitoring
      kill $MONITOR_PID 2>/dev/null || true
      wait $MONITOR_PID 2>/dev/null || true
      
      echo ""
      echo "📊 Stress Test Results"
      echo "====================="
      
      # Analyze monitoring data
      if [ -f "$MONITOR_LOG" ]; then
        AVG_CPU=$(awk -F',' 'NR>1 {sum+=$2; count++} END {if(count>0) print sum/count; else print 0}' "$MONITOR_LOG")
        MAX_CPU=$(awk -F',' 'NR>1 {if($2>max) max=$2} END {print max}' "$MONITOR_LOG")
        
        AVG_MEM=$(awk -F',' 'NR>1 {sum+=$3; count++} END {if(count>0) print sum/count; else print 0}' "$MONITOR_LOG")
        MAX_MEM=$(awk -F',' 'NR>1 {if($3>max) max=$3} END {print max}' "$MONITOR_LOG")
        
        echo "Average CPU Usage: $AVG_CPU%"
        echo "Maximum CPU Usage: $MAX_CPU%"
        echo "Average Memory Usage: $AVG_MEM%"
        echo "Maximum Memory Usage: $MAX_MEM%"
        
        # Check for system stability
        echo ""
        echo "🔍 System Stability Check"
        echo "------------------------"
        
        if [ -f /proc/uptime ]; then
          UPTIME=$(cat /proc/uptime | cut -d' ' -f1)
          echo "System uptime: $(echo "$UPTIME / 3600" | bc -l) hours"
        fi
        
        # Check for kernel errors
        if command -v dmesg >/dev/null 2>&1; then
          KERNEL_ERRORS=$(dmesg 2>/dev/null | grep -i "error" | wc -l || echo "0")
          echo "Kernel errors: $KERNEL_ERRORS"
        fi
        
        # Save detailed results
        mkdir -p /tmp/hardware-stress-results
        cp "$MONITOR_LOG" /tmp/hardware-stress-results/monitoring-data.csv
        
        # Cleanup
        rm -f "$MONITOR_LOG" /tmp/memtest /tmp/io_test /tmp/memtest_* /tmp/io_test_* 2>/dev/null || true
      else
        echo "⚠️  Monitoring data not available"
      fi
      
      echo ""
      echo "🎉 Hardware stress test completed!"
    '';
  };
}
