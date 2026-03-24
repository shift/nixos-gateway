{
  description = "XDP/eBPF Data Plane Acceleration Example";

  # Example configuration demonstrating XDP/eBPF acceleration
  # for high-performance packet processing and DDoS protection

  networking.acceleration.xdp = {
    enable = true;

    interfaces = {
      # WAN interface with packet dropping for DDoS protection
      wan = {
        enable = true;
        mode = "driver"; # Native driver mode for best performance
        program = "drop";
        blacklist = [
          "192.168.100.100" # Known malicious IP
          "10.0.0.50" # Attack source
          "172.16.1.254" # Suspicious host
        ];
      };

      # LAN interface with monitoring only
      lan = {
        enable = true;
        mode = "skb"; # Generic mode for compatibility
        program = "monitor";
      };

      # Management interface with custom XDP program
      mgmt = {
        enable = true;
        mode = "skb";
        program = "drop";
        blacklist = [ "10.0.0.100" ]; # Block unauthorized access
        customSource = ''
          #include <linux/bpf.h>
          #include <bpf/bpf_helpers.h>

          SEC("xdp")
          int custom_mgmt_filter(struct xdp_md *ctx) {
              // Custom management interface filtering logic
              void *data_end = (void *)(long)ctx->data_end;
              void *data = (void *)(long)ctx->data;
              struct ethhdr *eth = data;
              
              if (data + sizeof(*eth) > data_end)
                  return XDP_PASS;
              
              // Only allow management protocols
              uint16_t eth_type = eth->h_proto;
              if (eth_type != __constant_htons(ETH_P_IP) &&
                  eth_type != __constant_htons(ETH_P_ARP))
                  return XDP_DROP;
              
              return XDP_PASS;
          }

          char _license[] SEC("license") = "GPL";
        '';
      };
    };

    monitoring = {
      enable = true;
      metricsPort = 9091;
      customMetrics = [
        {
          name = "xdp_drops_total";
          type = "counter";
          description = "Total packets dropped by XDP";
        }
        {
          name = "xdp_pass_total";
          type = "counter";
          description = "Total packets passed by XDP";
        }
        {
          name = "xdp_processing_time";
          type = "histogram";
          description = "XDP program processing time in microseconds";
        }
      ];
    };
  };

  # Example firewall zones that work with XDP
  services.gateway.data = {
    firewall.zones = {
      wan = {
        description = "WAN zone with XDP protection";
        interfaces = [ "wan" ];
        policy = "drop";
        rules = [
          {
            description = "Allow established connections";
            action = "accept";
            state = [
              "established"
              "related"
            ];
          }
        ];
      };

      lan = {
        description = "LAN zone with monitoring";
        interfaces = [ "lan" ];
        policy = "accept";
      };

      mgmt = {
        description = "Management zone";
        interfaces = [ "mgmt" ];
        policy = "drop";
        rules = [
          {
            description = "Allow SSH from management network";
            action = "accept";
            protocol = "tcp";
            destination.port = 22;
            source.network = "10.0.0.0/24";
          }
        ];
      };
    };
  };

  # Example monitoring configuration
  services.gateway.data = {
    monitoring = {
      enable = true;
      metrics = {
        exporters = [
          {
            name = "xdp-metrics";
            type = "prometheus";
            port = 9091;
            path = "/metrics";
          }
        ];
      };
    };
  };
}
