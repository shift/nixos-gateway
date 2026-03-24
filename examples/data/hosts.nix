{
  staticDHCPv4Assignments = [
    {
      name = "hass";
      macAddress = "00:04:4b:e4:f5:56";
      ipAddress = "192.168.1.3";
      type = "infrastructure";
      ipv6Address = "2001:313:37::3";
      prometheusPort = 9100;
    }
    {
      name = "upcore";
      macAddress = "00:e0:4c:01:54:f7";
      ipAddress = "192.168.1.2";
      type = "infrastructure";
      ipv6Address = "2001:313:37::2";
      prometheusPort = 9100;
    }
    {
      name = "tv1";
      macAddress = "70:af:24:14:5f:cd";
      ipAddress = "192.168.1.170";
      type = "media";
    }
    {
      name = "ap-00";
      macAddress = "a4:97:33:df:b0:2f";
      ipAddress = "192.168.1.20";
      type = "infrastructure";
    }
    {
      name = "ap-01";
      macAddress = "a4:97:33:df:99:a7";
      ipAddress = "192.168.1.21";
      type = "infrastructure";
    }
    {
      name = "ap-iot-00";
      macAddress = "e0:63:da:81:d5:56";
      ipAddress = "192.168.1.30";
      type = "iot";
    }
    {
      name = "sp111-03";
      macAddress = "bc:dd:c2:30:2a:ff";
      ipAddress = "192.168.1.106";
      type = "iot";
    }
    {
      name = "sp111-00";
      macAddress = "bc:dd:c2:30:37:58";
      ipAddress = "192.168.1.109";
      type = "iot";
    }
    {
      name = "netatmo-welcome-00";
      macAddress = "70:ee:50:14:de:b4";
      ipAddress = "192.168.1.110";
      type = "iot";
    }
    {
      name = "hue-01";
      macAddress = "00:17:88:22:aa:78";
      ipAddress = "192.168.1.124";
      type = "iot";
    }
    {
      name = "media-00";
      macAddress = "00:e0:4c:68:00:69";
      ipAddress = "192.168.1.129";
      type = "server";
      ipv6Address = "2001:313:37::14";
      prometheusPort = 9100;
    }
    {
      name = "Kids-Bedroom-TV";
      macAddress = "d0:c0:bf:2e:6d:38";
      ipAddress = "192.168.1.157";
      type = "media";
    }
    {
      name = "sp111-06";
      macAddress = "d8:f1:5b:d4:9b:8c";
      ipAddress = "192.168.1.158";
      type = "iot";
    }
    {
      name = "aqs00";
      macAddress = "ec:fa:bc:c5:0f:c6";
      ipAddress = "192.168.1.161";
      type = "iot";
    }
    {
      name = "sp111-04";
      macAddress = "2c:f4:32:b5:3d:49";
      ipAddress = "192.168.1.182";
      type = "iot";
    }
    {
      name = "sp111-07";
      macAddress = "d8:f1:5b:d4:9e:a8";
      ipAddress = "192.168.1.187";
      type = "iot";
    }
    {
      name = "home-mini-00";
      macAddress = "20:df:b9:8f:80:5c";
      ipAddress = "192.168.1.188";
      type = "iot";
    }
    {
      name = "sonos-one-00";
      macAddress = "54:2a:1b:20:02:f6";
      ipAddress = "192.168.1.189";
      type = "media";
    }
    {
      name = "nintendo-switch-00";
      macAddress = "cc:fb:65:96:1a:53";
      ipAddress = "192.168.1.194";
      type = "gaming";
    }
    {
      name = "pixel-6-pro-00";
      macAddress = "dc:e5:5b:15:7b:63";
      ipAddress = "192.168.1.201";
      type = "client";
    }
    {
      name = "sonos-one-01";
      macAddress = "78:28:ca:00:10:a4";
      ipAddress = "192.168.1.203";
      type = "media";
    }
    {
      name = "ifan03-2";
      macAddress = "d8:f1:5b:8d:ab:2b";
      ipAddress = "192.168.1.206";
      type = "iot";
    }
    {
      name = "sp111-05";
      macAddress = "24:62:ab:2f:57:4e";
      ipAddress = "192.168.1.210";
      type = "iot";
    }
    {
      name = "samsung-washer";
      macAddress = "28:6d:97:4a:10:cb";
      ipAddress = "192.168.1.219";
      type = "iot";
    }
    {
      name = "ifan03-1";
      macAddress = "dc:4f:22:aa:31:2f";
      ipAddress = "192.168.1.223";
      type = "iot";
    }
    {
      name = "sonos-sub-00";
      macAddress = "78:28:ca:e0:00:ec";
      ipAddress = "192.168.1.243";
      type = "media";
    }
    {
      name = "moto-g-7-plus";
      macAddress = "1e:ef:8f:ce:d0:60";
      ipAddress = "192.168.1.233";
      type = "client";
    }
    {
      name = "printer-epson-00";
      macAddress = "e0:bb:9e:5b:aa:58";
      ipAddress = "192.168.1.241";
      type = "iot";
    }
  ];

  staticDHCPv6Assignments = [
    {
      name = "ca-0";
      duid = "00:01:00:01:2a:be:8d:c8:dc:a6:32:d5:40:9b";
      address = "2001:313:37::6";
    }
    {
      name = "prumera-dio";
      duid = "00:01:00:01:27:8f:0a:6c:dc:a6:32:d5:4c:29";
      address = "2001:313:37::91b";
    }
    {
      name = "pc-0";
      duid = "00:03:00:01:44:d9:e7:9e:82:9a";
      address = "2001:313:37::c78";
    }
    {
      name = "media";
      duid = "00:04:2c:81:0b:36:54:75:c5:72:59:0a:75:c8:71:ca:37:0f";
      address = "2001:313:37::14";
    }
    {
      name = "dios-minecraft-pi";
      duid = "00:04:51:18:70:ff:b1:4f:c4:3e:4c:43:ec:62:26:e4:ea:cb";
      address = "2001:313:37::15";
    }
    {
      name = "dio-print";
      duid = "00:01:00:01:29:dd:b4:fe:e4:5f:01:54:29:89";
      address = "2001:313:37::5aa";
    }
    {
      name = "mcs";
      duid = "00:04:65:1d:1e:99:53:cd:5f:bb:53:84:3d:63:06:3e:6f:59";
      address = "2001:313:37::d10";
    }
    {
      name = "carbonadium";
      duid = "6c:4b:90:5f:9a:d1";
      address = "2001:313:37::29";
    }
    {
      name = "vibranium";
      duid = "44:af:28:f0:58:a7";
      address = "2001:313:37::28";
    }
  ];
}
