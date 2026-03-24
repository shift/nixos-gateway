{
  zones = {
    green = {
      description = "Internal trusted network (LAN)";
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
      description = "Management network";
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
      description = "External untrusted network (WAN/WWAN/WiFi)";
      allowedTCPPorts = [ ];
      allowedUDPPorts = [ ];
    };
  };

  deviceTypePolicies = {
    iot = {
      description = "IoT devices - restricted to HTTP/HTTPS only";
      allowedTCPPorts = [
        80
        443
      ];
      allowedUDPPorts = [
        53
        123
      ];
    };

    media = {
      description = "Media devices - standard access";
      allowedTCPPorts = [
        80
        443
      ];
      allowedUDPPorts = [
        53
        123
      ];
    };

    server = {
      description = "Server devices - full access";
      allowedTCPPorts = [
        22
        53
        80
        443
      ];
      allowedUDPPorts = [
        53
        123
      ];
    };

    infrastructure = {
      description = "Infrastructure devices - full access including management";
      allowedTCPPorts = [
        22
        53
        80
        443
        9090
      ];
      allowedUDPPorts = [
        53
        123
      ];
    };

    client = {
      description = "Client devices - full access";
      allowedTCPPorts = [
        22
        53
        80
        443
        3389
        5201
      ];
      allowedUDPPorts = [
        53
        67
        68
        123
        547
        5201
      ];
    };

    gaming = {
      description = "Gaming devices - optimized for low latency";
      allowedTCPPorts = [
        80
        443
      ];
      allowedUDPPorts = [
        53
        123
      ];
      allowedUDPPortRanges = [
        {
          from = 27000;
          to = 27100;
        }
      ];
    };
  };
}
