{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.loadBalancing;
  inherit (lib)
    mkOption
    types
    mkIf
    mkEnableOption
    ;

  # Submodule for individual server definition (IP:Port + Params)
  serverOptions = types.submodule {
    options = {
      address = mkOption {
        type = types.str;
        description = "IP address or hostname of the backend server";
      };
      port = mkOption {
        type = types.int;
        description = "Port number of the backend server";
      };
      weight = mkOption {
        type = types.int;
        default = 1;
        description = "Weight for weighted load balancing algorithms";
      };
      maxFails = mkOption {
        type = types.int;
        default = 1;
        description = "Number of unsuccessful attempts before server is marked down";
      };
      failTimeout = mkOption {
        type = types.str;
        default = "10s";
        description = "Time during which max_fails must occur to mark server down";
      };
    };
  };

  # Submodule for Upstream Groups
  upstreamOptions = types.submodule {
    options = {
      servers = mkOption {
        type = types.listOf serverOptions;
        description = "List of backend servers";
      };
      algorithm = mkOption {
        type = types.enum [
          "round-robin"
          "least_conn"
          "ip_hash"
        ];
        default = "round-robin";
        description = "Load balancing algorithm";
      };
      protocol = mkOption {
        type = types.enum [
          "http"
          "tcp"
          "udp"
        ];
        default = "http";
        description = "Protocol type for this upstream group (http = L7, tcp/udp = L4)";
      };
    };
  };

  # Submodule for Virtual Servers (Listeners)
  virtualServerOptions = types.submodule {
    options = {
      listenAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Address to listen on";
      };
      port = mkOption {
        type = types.int;
        description = "Port to listen on";
      };
      protocol = mkOption {
        type = types.enum [
          "http"
          "tcp"
          "udp"
        ];
        default = "http";
        description = "Protocol type (HTTP for L7, TCP/UDP for L4)";
      };
      upstream = mkOption {
        type = types.str;
        description = "Name of the upstream group to forward traffic to";
      };
      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Domain name for HTTP virtual hosts (optional, for L7 only)";
      };
    };
  };

in
{
  options.services.gateway.loadBalancing = {
    enable = mkEnableOption "Load Balancing Service";

    upstreams = mkOption {
      type = types.attrsOf upstreamOptions;
      default = { };
      description = "Backend server groups (Upstreams)";
      example = {
        web_backend = {
          protocol = "http";
          algorithm = "least_conn";
          servers = [
            {
              address = "192.168.1.10";
              port = 80;
              weight = 5;
            }
            {
              address = "192.168.1.11";
              port = 80;
              weight = 1;
            }
          ];
        };
      };
    };

    virtualServers = mkOption {
      type = types.attrsOf virtualServerOptions;
      default = { };
      description = "Frontend listeners (Virtual Servers)";
      example = {
        main_website = {
          listenAddress = "0.0.0.0";
          port = 80;
          protocol = "http";
          upstream = "web_backend";
          domain = "example.com";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    services.nginx = {
      enable = true;
      package = pkgs.nginxMainline.override { withStream = true; };

      # Layer 7 (HTTP) Configuration - Integrated into main nginx.conf via virtualHosts and appendHttpConfig
      virtualHosts = lib.mkMerge (
        lib.mapAttrsToList (
          name: vs:
          if vs.protocol == "http" then
            {
              "${if vs.domain != null then vs.domain else "default-${name}"}" = {
                listen = [
                  {
                    addr = vs.listenAddress;
                    port = vs.port;
                  }
                ];
                locations."/" = {
                  proxyPass = "http://${vs.upstream}";
                  extraConfig = ''
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  '';
                };
              };
            }
          else
            { }
        ) cfg.virtualServers
      );

      appendHttpConfig =
        let
          httpUpstreams = lib.filterAttrs (n: u: u.protocol == "http") cfg.upstreams;
        in
        ''
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: u: ''
              upstream ${name} {
                ${
                  if u.algorithm == "ip_hash" then
                    "ip_hash;"
                  else if u.algorithm == "least_conn" then
                    "least_conn;"
                  else
                    ""
                }
                ${lib.concatMapStringsSep "\n    " (
                  s:
                  "server ${s.address}:${toString s.port} weight=${toString s.weight} max_fails=${toString s.maxFails} fail_timeout=${s.failTimeout};"
                ) u.servers}
              }
            '') httpUpstreams
          )}
        '';

      # Layer 4 (Stream) Configuration - For TCP/UDP
      streamConfig =
        let
          streamUpstreams = lib.filterAttrs (n: u: u.protocol == "tcp" || u.protocol == "udp") cfg.upstreams;
          streamServers = lib.filterAttrs (
            n: vs: vs.protocol == "tcp" || vs.protocol == "udp"
          ) cfg.virtualServers;
        in
        ''
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: u: ''
              upstream ${name} {
                ${if u.algorithm == "least_conn" then "least_conn;" else ""}
                # ip_hash is not supported in stream module directly in same way, hash $remote_addr consistent is used usually
                ${if u.algorithm == "ip_hash" then "hash $remote_addr consistent;" else ""}
                ${lib.concatMapStringsSep "\n    " (
                  s:
                  "server ${s.address}:${toString s.port} weight=${toString s.weight} max_fails=${toString s.maxFails} fail_timeout=${s.failTimeout};"
                ) u.servers}
              }
            '') streamUpstreams
          )}

          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: vs: ''
              server {
                listen ${vs.listenAddress}:${toString vs.port} ${if vs.protocol == "udp" then "udp" else ""};
                proxy_pass ${vs.upstream};
              }
            '') streamServers
          )}
        '';
    };

    # Open Firewall Ports
    networking.firewall.allowedTCPPorts = lib.map (vs: vs.port) (
      lib.filter (vs: vs.protocol != "udp") (lib.attrValues cfg.virtualServers)
    );

    networking.firewall.allowedUDPPorts = lib.map (vs: vs.port) (
      lib.filter (vs: vs.protocol == "udp") (lib.attrValues cfg.virtualServers)
    );

    # Generate a JSON config dump for external tools/inspection
    environment.etc."gateway/load-balancing/config.json".text = builtins.toJSON {
      upstreams = cfg.upstreams;
      virtualServers = cfg.virtualServers;
    };
  };
}
