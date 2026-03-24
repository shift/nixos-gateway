{
  ruleSources = {
    emergingThreats = {
      url = "https://rules.emergingthreats.net/open/suricata/emerging.rules.tar.gz";
      sha256 = "0h3v2m4h4y88a44d0f5i311nplb11n10y50f6h614d9q052";
      enabled = true;
    };
  };

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
