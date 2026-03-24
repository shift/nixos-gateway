{ type }:

if type == "firewall" then
  {
    zones = {
      green = {
        allowedTCPPorts = [
          22
          53
          80
          443
          3389
          5201
          8123
        ];
        allowedUDPPorts = [
          53
          67
          68
          123
          547
          5201
          8123
        ];
      };
      mgmt = {
        allowedTCPPorts = [
          22
          53
          80
          443
          9090
          9142
        ];
        allowedUDPPorts = [ 53 ];
      };
      red = {
        allowedTCPPorts = [ ];
        allowedUDPPorts = [ ];
      };
    };

    deviceTypes = {
      iot = {
        allowInternet = true;
        allowLAN = false;
        allowedDestinations = [ ];
      };
      workstation = {
        allowInternet = true;
        allowLAN = true;
        allowedDestinations = [ ];
      };
      server = {
        allowInternet = true;
        allowLAN = true;
        allowedDestinations = [ ];
      };
    };
  }
else if type == "ids" then
  {
    detectEngine = {
      profile = "high";
      sghMpmContext = "auto";
      mpmAlgo = "hs";
    };

    threading = {
      setCpuAffinity = true;
      managementCpus = [ 0 ];
      workerCpus = [
        1
        2
        3
      ];
    };

    protocols = {
      http = {
        enabled = true;
      };
      tls = {
        enabled = true;
        ports = [ 443 ];
      };
      dns = {
        enabled = true;
        tcp = true;
        udp = true;
      };
      modbus = {
        enabled = true;
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
          "files"
          "flow"
          "drop"
        ];
      };
      rotation = {
        logs = {
          days = 7;
          compress = true;
        };
        json = {
          days = 30;
          compress = true;
          maxSize = "1G";
        };
      };
    };

    exporter = {
      port = 9917;
      socketPath = "/run/suricata/suricata.socket";
    };
  }
else
  throw "Unknown default data type: ${type}"
