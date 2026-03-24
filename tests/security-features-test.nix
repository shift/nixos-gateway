# Security Features Test
# Task: 22, 23, 24, 25
# Feature: Zero Trust, Threat Intelligence, Access Control
# Tags: security, zero-trust, compliance

{
  # Test security configuration
  services.gateway = {
    enable = true;
    interfaces = {
      wan = "eth0";
      lan = "eth1";
      dmz = "eth2";
    };

    # Test Zero Trust Microsegmentation (Task 22)
    zeroTrust = {
      enable = true;
      identityProvider = "azure-ad";
      policies = {
        developers = {
          access = [
            "dev-environment"
            "staging"
          ];
          timeRestrictions = "business-hours";
          mfaRequired = true;
        };
        administrators = {
          access = [
            "production"
            "infrastructure"
          ];
          timeRestrictions = "24x7";
          mfaRequired = true;
          approvalRequired = true;
        };
      };
    };

    # Test Threat Intelligence Integration (Task 23)
    threatIntelligence = {
      enable = true;
      feeds = [
        "https://threat-feed.example.com/ips"
        "https://threat-feed.example.com/domains"
        "https://threat-feed.example.com/hashes"
      ];
      updateInterval = "1h";
      action = "block";
    };

    # Test Device Posture Assessment (Task 24)
    devicePosture = {
      enable = true;
      checks = {
        osVersion = {
          minimum = "10.15";
          action = "block";
        };
        antivirus = {
          enabled = true;
          updated = true;
          action = "warn";
        };
        diskEncryption = {
          enabled = true;
          action = "block";
        };
      };
    };

    # Test Time-Based Access Controls (Task 25)
    timeBasedAccess = {
      enable = true;
      schedules = {
        businessHours = {
          days = [
            "monday"
            "tuesday"
            "wednesday"
            "thursday"
            "friday"
          ];
          hours = "09:00-17:00";
          timezone = "UTC";
        };
        maintenanceWindow = {
          days = [ "sunday" ];
          hours = "02:00-04:00";
          timezone = "UTC";
          access = "administrators-only";
        };
      };
    };

    # Test IP Reputation Blocking (Task 26)
    ipReputation = {
      enable = true;
      sources = [
        "spamhaus"
        "abuseipdb"
        "custom"
      ];
      threshold = 5;
      action = "block";
      duration = "24h";
    };
  };

  # Test validation
  testAssertions = [
    {
      description = "Zero Trust should be enabled";
      assertion = config.services.gateway.zeroTrust.enable == true;
    }
    {
      description = "Threat Intelligence should be enabled";
      assertion = config.services.gateway.threatIntelligence.enable == true;
    }
    {
      description = "Device Posture should be enabled";
      assertion = config.services.gateway.devicePosture.enable == true;
    }
    {
      description = "Time-Based Access should be enabled";
      assertion = config.services.gateway.timeBasedAccess.enable == true;
    }
    {
      description = "IP Reputation should be enabled";
      assertion = config.services.gateway.ipReputation.enable == true;
    }
    {
      description = "MFA should be required for developers";
      assertion = config.services.gateway.zeroTrust.policies.developers.mfaRequired == true;
    }
    {
      description = "Business hours should be configured";
      assertion = config.services.gateway.timeBasedAccess.schedules.businessHours.hours == "09:00-17:00";
    }
  ];
}
