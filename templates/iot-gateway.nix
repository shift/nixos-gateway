{ lib }:

{
  name = "IoT Gateway";
  description = "IoT gateway with device isolation, specialized protocols, and edge processing";

  parameters = {
    lanInterface = {
      type = "string";
      required = true;
      description = "Management interface";
    };
    iotInterface = {
      type = "string";
      required = true;
      description = "IoT devices interface";
    };
    wanInterface = {
      type = "string";
      required = true;
      description = "Internet/WAN interface";
    };
    domain = {
      type = "string";
      default = "iot.local";
      description = "IoT domain name";
    };
    iotNetwork = {
      type = "cidr";
      default = "192.168.100.0/24";
      description = "IoT device network";
    };
    iotGateway = {
      type = "ip";
      default = "192.168.100.1";
      description = "IoT gateway IP";
    };
    managementNetwork = {
      type = "cidr";
      default = "192.168.1.0/24";
      description = "Management network";
    };
    managementGateway = {
      type = "ip";
      default = "192.168.1.1";
      description = "Management gateway IP";
    };
    enableMQTT = {
      type = "bool";
      default = true;
      description = "Enable MQTT broker";
    };
    enableCoAP = {
      type = "bool";
      default = true;
      description = "Enable CoAP support";
    };
    enableModbus = {
      type = "bool";
      default = false;
      description = "Enable Modbus protocol support";
    };
    enableEdgeProcessing = {
      type = "bool";
      default = true;
      description = "Enable edge data processing";
    };
    deviceTypes = {
      type = "array";
      default = [
        "sensor"
        "actuator"
        "camera"
        "controller"
      ];
      description = "Supported IoT device types";
    };
  };

  config =
    {
      lanInterface,
      iotInterface,
      wanInterface,
      domain,
      iotNetwork,
      iotGateway,
      managementNetwork,
      managementGateway,
      enableMQTT,
      enableCoAP,
      enableModbus,
      enableEdgeProcessing,
      deviceTypes,
      ...
    }:
    {
      services.gateway = {
        enable = true;
        interfaces = {
          lan = lanInterface;
          iot = iotInterface;
          wan = wanInterface;
        };
        domain = domain;

        data = {
          network = {
            subnets = {
              iot = {
                ipv4 = {
                  subnet = iotNetwork;
                  gateway = iotGateway;
                };
              };
              management = {
                ipv4 = {
                  subnet = managementNetwork;
                  gateway = managementGateway;
                };
              };
            };

            dhcp = {
              poolStart = "192.168.100.100";
              poolEnd = "192.168.100.200";
            };
          };

          hosts = {
            staticDHCPv4Assignments = [ ];
            staticDHCPv6Assignments = [ ];
          };

          firewall = {
            zones = {
              iot = {
                description = "IoT devices zone";
                allowedTCPPorts = [
                  1883
                  8883
                ]; # MQTT
                allowedUDPPorts = [
                  53
                  67
                  68
                  5683
                ]; # DNS, DHCP, CoAP
              };
              mgmt = {
                description = "Management zone";
                allowedTCPPorts = [
                  22
                  53
                  80
                  443
                  1883
                ];
                allowedUDPPorts = [ 53 ];
              };
              red = {
                description = "Internet zone";
                allowedTCPPorts = [
                  443
                  8883
                ]; # HTTPS, MQTTS
                allowedUDPPorts = [ 53 ];
              };
            };

            deviceTypePolicies = {
              sensor = {
                description = "IoT sensors";
                allowedTCPPorts = [ 1883 ];
                allowedUDPPorts = [ 5683 ];
                allowInternet = true;
                allowLAN = false;
              };
              actuator = {
                description = "IoT actuators";
                allowedTCPPorts = [ 1883 ];
                allowedUDPPorts = [ 5683 ];
                allowInternet = false;
                allowLAN = true;
              };
              camera = {
                description = "IP cameras";
                allowedTCPPorts = [
                  80
                  443
                  554
                ];
                allowedUDPPorts = [ 53 ];
                allowInternet = false;
                allowLAN = true;
              };
              controller = {
                description = "IoT controllers";
                allowedTCPPorts = [
                  22
                  80
                  443
                  1883
                ];
                allowedUDPPorts = [ 53 ];
                allowInternet = true;
                allowLAN = true;
              };
            };
          };

          ids = {
            detectEngine = {
              profile = "medium";
              sghMpmContext = "auto";
              mpmAlgo = "hs";
            };

            protocols = {
              http = {
                enabled = true;
              };
              tls = {
                enabled = true;
                ports = [
                  443
                  8883
                ];
              };
              dns = {
                enabled = true;
                tcp = true;
                udp = true;
              };
              mqtt = {
                enabled = enableMQTT;
              };
              modbus = {
                enabled = enableModbus;
                detectionEnabled = true;
              };
            };

            logging = {
              eveLog = {
                enabled = true;
                types = [
                  "alert"
                  "http"
                  "dns"
                  "tls"
                  "mqtt"
                ];
              };
            };
          };
        };
      };

      networking.firewall.enable = false;
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };

      # MQTT broker for IoT communication
      services.mosquitto = lib.mkIf enableMQTT {
        enable = true;
        listeners = [
          {
            address = "0.0.0.0";
            port = 1883;
            settings = {
              allow_anonymous = true;
            };
          }
          {
            address = "0.0.0.0";
            port = 8883;
            settings = {
              allow_anonymous = false;
              cafile = "/etc/mosquitto/ca.crt";
              certfile = "/etc/mosquitto/server.crt";
              keyfile = "/etc/mosquitto/server.key";
            };
          }
        ];
      };

      # CoAP support (would need additional packages)
      services.coap-server = lib.mkIf enableCoAP {
        enable = true;
        # CoAP server configuration
      };

      # Edge processing capabilities
      virtualisation.oci-containers = lib.mkIf enableEdgeProcessing {
        backend = "docker";
        containers = {
          edge-processor = {
            image = "nginx:alpine";
            ports = [ "8080:80" ];
            volumes = [ "/var/lib/edge-data:/data" ];
          };
        };
      };

      # IoT device discovery and management
      services.avahi = {
        enable = true;
        publish = {
          enable = true;
          addresses = true;
          workstation = true;
        };
      };
    };
}
