{
  subnets = {
    lan = {
      ipv4 = {
        subnet = "192.168.1.0/24";
        gateway = "192.168.1.1";
      };
      ipv6 = {
        prefix = "2001:470:50df::/48";
        gateway = "2001:470:50df::1";
      };
    };
  };

  mgmtAddress = "192.168.1.148";

  dhcp = {
    poolStart = "192.168.1.50";
    poolEnd = "192.168.1.254";
  };
}
