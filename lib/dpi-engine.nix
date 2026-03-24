{ lib }:

with lib;

let
  # A simulated database of application signatures to L3/L4 rules.
  # In a real DPI implementation, this would map to nDPI protocols or L7 patterns.
  # For now, we map them to known ports/protocols to enforce shaping.
  appDatabase = {
    # Streaming
    "netflix" = {
      protocols = [ "tcp" ];
      ports = [
        80
        443
      ]; # Broad, but standard for HTTPS streaming
      domains = [
        "netflix.com"
        "nflxvideo.net"
      ];
    };
    "youtube" = {
      protocols = [
        "tcp"
        "udp"
      ];
      ports = [
        80
        443
      ];
      domains = [
        "youtube.com"
        "googlevideo.com"
      ];
    };
    "twitch" = {
      protocols = [ "tcp" ];
      ports = [
        80
        443
        1935
      ];
      domains = [ "twitch.tv" ];
    };

    # VoIP
    "zoom" = {
      protocols = [
        "tcp"
        "udp"
      ];
      ports = [
        8801
        8802
      ]; # partial list
    };
    "teams" = {
      protocols = [
        "tcp"
        "udp"
      ];
      ports = [
        3478
        3479
        3480
        3481
      ];
    };
    "slack-voice" = {
      protocols = [ "udp" ];
      ports = [ 22466 ];
    };

    # File Sharing
    "bittorrent" = {
      protocols = [
        "tcp"
        "udp"
      ];
      ports = [
        6881
        6882
        6883
        6884
        6885
        6886
        6887
        6888
        6889
      ]; # Classic range, though often random
    };

    # Generic
    "http" = {
      protocols = [ "tcp" ];
      ports = [ 80 ];
    };
    "https" = {
      protocols = [ "tcp" ];
      ports = [ 443 ];
    };
    "ssh" = {
      protocols = [ "tcp" ];
      ports = [ 22 ];
    };
  };

  # Helper to resolve application signatures to nftables matchers
  resolveAppToRules =
    appName:
    if hasAttr appName appDatabase then
      let
        app = appDatabase.${appName};
        # Create a simplified rule that matches either TCP or UDP on the specified ports

        # Flattened list of { proto, port }
        rules = flatten (
          map (proto: map (port: { inherit proto port; }) (app.ports or [ ])) (app.protocols or [ ])
        );

        matchers = map (r: "meta l4proto ${r.proto} th dport ${toString r.port}") rules;
      in
      matchers
    else
      [ ]; # Unknown app

  # Helper to resolve a list of application signatures to a list of rules
  resolveApps = apps: flatten (map resolveAppToRules apps);

in
{
  inherit appDatabase;
  inherit resolveAppToRules;
  inherit resolveApps;

  # Function to generate a traffic class definition for qos.nix from an app-aware definition
  mkQoSClass = name: appConfig: priority: {
    id = 100 + priority; # Offset to avoid collision with default classes
    priority = appConfig.shaping.priority or 5;
    maxBandwidth = appConfig.shaping.maxBandwidth or "1Gbit";
    guaranteedBandwidth = appConfig.shaping.guaranteedBandwidth or "1Mbit";
    # We pass the raw protocols/signatures to be handled by the specialized matcher logic
    protocols = appConfig.protocols or [ ];
  };
}
